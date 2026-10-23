require 'rails_helper'

RSpec.describe 'Arroyo commercial follow-ups API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:seller) { create(:user, account: account, role: :agent, name: 'Marcos Peralta') }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:conversation) { create(:conversation, account: account, inbox: channel.inbox, assignee: seller) }
  let(:base) { "/api/v1/accounts/#{account.id}/arroyo/commercial/follow_ups" }
  let(:zone) { ActiveSupport::TimeZone['America/Argentina/Buenos_Aires'] }

  def configure(funnel:)
    setting = Arroyo::Setting.for(account)
    setting.merge_config(agent_panel: { enabled: true, funnel_enabled: funnel, seller_ids: [seller.id] })
    setting.save!
  end

  def opportunity
    Arroyo::Opportunity.find_by!(conversation: conversation)
  end

  def payload
    { conversation_id: conversation.display_id, opportunity_reference: opportunity.reference }
  end

  before do
    configure(funnel: true)
    channel.update!(message_templates: %w[seg_dia_1 seg_dia_3 seg_dia_5].map do |name|
      { name: name, language: 'es_AR', status: 'APPROVED', category: 'MARKETING', parameter_format: 'NAMED',
        components: [{ type: 'BODY', text: 'Soy {{asesor}}. ¿Seguimos con {{producto}}?' }] }
    end)
    travel_to(zone.parse('2026-10-20 18:30')) do
      create(:message, account: account, conversation: conversation, message_type: :incoming)
      conversation.reload.update!(label_list: ['seguimiento'])
    end
    travel_to zone.parse('2026-10-21 10:00')
  end

  describe 'GET /follow_ups' do
    it 'lists the follow-ups with their steps, alias and agenda' do
      get base, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:ok)
      row = response.parsed_body['follow_ups'].sole
      expect(row).to include('conversation_id' => conversation.display_id, 'status' => 'scheduled', 'advisor_alias' => 'Marcos',
                             'next_at' => '2026-10-21T10:00:00-03:00', 'next_step' => 1, 'due_today' => true,
                             'can_send_now' => true, 'can_reschedule' => true, 'can_enroll' => false, 'blocked_reason' => nil)
      expect(row['steps'].map { |step| step['status'] }).to eq(%w[scheduled pending pending])
      expect(response.parsed_body['totals']).to include('scheduled' => 1, 'unenrolled' => 0)
      expect(response.parsed_body['agenda']).to eq([{ 'date' => '2026-10-21', 'count' => 1 }])
    end

    it 'lists labelled chats that were never enrolled together with what the previous flow sent' do
      configure(funnel: false)
      legacy = create(:conversation, account: account, inbox: channel.inbox, assignee: seller,
                                     custom_attributes: { seguimiento_envios: 2, seguimiento_ultimo_envio: '2026-10-19' })
      legacy.update!(label_list: ['seguimiento'])
      configure(funnel: true)
      get base, headers: admin.create_new_auth_token

      row = response.parsed_body['follow_ups'].find { |item| item['conversation_id'] == legacy.display_id }
      expect(row).to include('status' => 'unenrolled', 'sent_count' => 2, 'can_enroll' => true, 'can_send_now' => false,
                             'opportunity_reference' => nil, 'blocked_reason' => 'not_enrolled')
      expect(row['steps'].map { |step| step['status'] }).to eq(%w[sent sent pending])
      expect(response.parsed_body['totals']).to include('scheduled' => 1, 'unenrolled' => 1)
    end

    it 'is limited to administrators and to accounts with the funnel on' do
      get base, headers: seller.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)

      configure(funnel: false)
      get base, headers: admin.create_new_auth_token
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'POST /follow_ups/send_now' do
    it 'sends the next step immediately, even before its day' do
      headers = admin.create_new_auth_token
      post "#{base}/send_now", params: payload, headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('follow_up', 'sent_count')).to eq(1)

      post "#{base}/send_now", params: payload, headers: headers
      expect(response.parsed_body.dig('follow_up', 'sent_count')).to eq(2)
      expect(opportunity.commercial_messages.size).to eq(2)
    end
  end

  describe 'PATCH /follow_ups/reschedule' do
    it 'moves the next send to a later day' do
      patch "#{base}/reschedule", params: payload.merge(date: '2026-10-27'), headers: admin.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('follow_up', 'next_at')).to eq('2026-10-27T10:00:00-03:00')
      expect(response.parsed_body.dig('follow_up', 'due_today')).to be(false)
    end

    it 'rejects today, past and malformed dates' do
      headers = admin.create_new_auth_token
      %w[2026-10-21 2026-10-01 mañana].each do |date|
        patch "#{base}/reschedule", params: payload.merge(date: date), headers: headers

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['code']).to eq('invalid_date')
      end
    end
  end

  describe 'POST /follow_ups/enroll' do
    it 'enrolls labelled chats for the next day and reports the ones it skipped' do
      configure(funnel: false)
      pending_chat = create(:conversation, account: account, inbox: channel.inbox, assignee: seller)
      pending_chat.update!(label_list: ['seguimiento'])
      configure(funnel: true)
      unlabelled = create(:conversation, account: account, inbox: channel.inbox, assignee: seller)

      post "#{base}/enroll", params: { conversation_ids: [pending_chat.display_id, unlabelled.display_id, 999_999] },
                             headers: admin.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['enrolled']).to eq([pending_chat.display_id])
      expect(response.parsed_body['skipped']).to contain_exactly({ 'conversation_id' => unlabelled.display_id, 'reason' => 'not_eligible' },
                                                                 { 'conversation_id' => 999_999, 'reason' => 'not_found' })
      get base, headers: admin.create_new_auth_token
      row = response.parsed_body['follow_ups'].find { |item| item['conversation_id'] == pending_chat.display_id }
      expect(row).to include('status' => 'scheduled', 'next_at' => '2026-10-22T10:00:00-03:00')
    end
  end
end
