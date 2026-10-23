require 'rails_helper'

RSpec.describe 'Arroyo follow-up enrollment API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:conversation) { create(:conversation, account: account, inbox: channel.inbox, assignee: seller) }
  let(:base) { "/api/v1/accounts/#{account.id}/arroyo/commercial" }
  let(:zone) { ActiveSupport::TimeZone['America/Argentina/Buenos_Aires'] }

  before do
    setting = Arroyo::Setting.for(account)
    setting.merge_config(agent_panel: { enabled: true, funnel_enabled: true, seller_ids: [seller.id] })
    setting.save!
    travel_to(zone.parse('2026-10-20 18:30')) do
      create(:message, account: account, conversation: conversation, message_type: :incoming)
      conversation.reload.update!(label_list: ['seguimiento'])
    end
    travel_to zone.parse('2026-10-21 10:00')
    channel.update!(message_templates: %w[seg_dia_1 seg_dia_3 seg_dia_5].map do |name|
      { name: name, language: 'es_AR', status: 'APPROVED', category: 'MARKETING', parameter_format: 'NAMED',
        components: [{ type: 'BODY', text: 'Soy {{asesor}}. ¿Seguimos con {{producto}}?' }] }
    end)
  end

  def opportunity
    Arroyo::Opportunity.find_by!(conversation: conversation)
  end

  def payload
    { conversation_id: conversation.display_id, opportunity_reference: opportunity.reference, step: 1 }
  end

  it 'publishes an eligible next-day schedule independently of pending human attention' do
    get "#{base}/contexts", params: { conversation_id: conversation.display_id }, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    context = response.parsed_body['contexts'].sole
    expect(context['state']).to eq('pending')
    expect(context['last_human_at']).to be_nil
    expect(context['commercial_allowed']).to be(true)
    expect(context['follow_up']).to include('active' => true, 'due' => true, 'sent_count' => 0, 'next_at' => '2026-10-21T10:00:00-03:00')
  end

  it 'dispatches one fixed Meta template and deduplicates the same step without a human reply' do
    headers = admin.create_new_auth_token
    post "#{base}/follow_up/message", params: payload, headers: headers
    expect(response).to have_http_status(:ok)
    message_id = response.parsed_body['id']
    post "#{base}/follow_up/message", params: payload, headers: headers
    expect(response.parsed_body['id']).to eq(message_id)
    expect(opportunity.commercial_messages.size).to eq(1)
    expect(Message.find(message_id).additional_attributes.dig('template_params', 'name')).to eq('seg_dia_1')
  end

  it 'rechecks removal of the label after n8n read an eligible context' do
    get "#{base}/contexts", headers: admin.create_new_auth_token
    expect(response.parsed_body['contexts'].sole.dig('follow_up', 'due')).to be(true)
    conversation.reload.update!(label_list: ['bici'])
    post "#{base}/follow_up/message", params: payload, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:unprocessable_entity)
    expect(opportunity.commercial_messages).to be_empty
  end

  it 'does not complete an unfinished sequence or grant completion access to sellers' do
    post "#{base}/follow_up/complete", params: payload.except(:step), headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['completed']).to be(false)
    expect(conversation.reload.label_list).to include('seguimiento')
    post "#{base}/follow_up/complete", params: payload.except(:step), headers: seller.create_new_auth_token
    expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
  end
end
