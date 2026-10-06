require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Arroyo::AgentPanelController', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator, name: 'Admin') }
  let(:seller) { create(:user, account: account, role: :agent, name: 'Julieta') }
  let(:other_seller) { create(:user, account: account, role: :agent, name: 'Marcos') }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: seller) }
  let(:other_conversation) { create(:conversation, account: account, inbox: inbox, assignee: seller) }
  let(:url) { "/api/v1/accounts/#{account.id}/arroyo/agent_panel" }
  let(:params) { { since: '2026-10-01', until: '2026-10-02' } }
  let(:argentina) { ActiveSupport::TimeZone['America/Argentina/Buenos_Aires'] }

  def agent_row(body, user)
    body['agents'].find { |agent| agent['id'] == user.id }
  end

  before do
    Arroyo::Setting.for(account).tap { |setting| setting.merge_config(agent_panel: { enabled: true }) }.save!
  end

  describe 'GET /api/v1/accounts/{account.id}/arroyo/agent_panel' do
    it 'returns unauthorized for unauthenticated users' do
      get url, params: params

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns forbidden when the panel is disabled' do
      Arroyo::Setting.for(account).tap { |setting| setting.merge_config(agent_panel: { enabled: false }) }.save!

      get url, headers: administrator.create_new_auth_token, params: params

      expect(response).to have_http_status(:forbidden)
    end

    it 'returns unprocessable entity for invalid filters' do
      get url, headers: administrator.create_new_auth_token, params: { since: '01/10/2026', until: '2026-10-02' }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['errors']).to eq(['Since is invalid'])

      get url, headers: administrator.create_new_auth_token, params: params.merge(inbox_ids: [create(:inbox).id])
      expect(response).to have_http_status(:unprocessable_entity)
    end

    context 'with activity around midnight in Argentina' do
      before do
        create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :outgoing, sender: seller,
                         created_at: argentina.parse('2026-10-01 15:00'))
        # 23:30 en Argentina es 02:30 UTC del día siguiente: tiene que contar para el 1/10
        create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :outgoing, sender: seller,
                         created_at: argentina.parse('2026-10-01 23:30'))
        create(:message, account: account, conversation: other_conversation, inbox: inbox, message_type: :outgoing, sender: seller,
                         created_at: argentina.parse('2026-10-02 10:00'))
        # No cuentan: nota privada, mensaje automático (sender nil), entrante y fuera de rango
        create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :outgoing, sender: seller,
                         private: true, created_at: argentina.parse('2026-10-01 16:00'))
        create(:message, :bot_message, account: account, conversation: conversation, inbox: inbox,
                                       created_at: argentina.parse('2026-10-01 16:00'))
        create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :incoming,
                         created_at: argentina.parse('2026-10-01 16:00'))
        create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :outgoing, sender: seller,
                         created_at: argentina.parse('2026-10-03 00:30'))

        create(:reporting_event, account: account, inbox: inbox, user: seller, conversation: conversation, value: 60,
                                 created_at: argentina.parse('2026-10-01 15:00'))
        create(:reporting_event, account: account, inbox: inbox, user: seller, conversation: other_conversation, value: 120,
                                 created_at: argentina.parse('2026-10-01 18:00'))
        Arroyo::AssignmentEvent.create!(account: account, conversation: other_conversation, inbox: inbox, assignee: seller,
                                        created_at: argentina.parse('2026-10-02 09:00'))
        travel_to(argentina.parse('2026-10-01 20:00')) { conversation.update!(label_list: ['vendido']) }
        travel_to(argentina.parse('2026-10-02 23:50')) { other_conversation.update!(label_list: [Arroyo::WINDOW_CLOSED_LABEL]) }
      end

      it 'groups every metric by local day and agent' do
        get url, headers: administrator.create_new_auth_token, params: params

        expect(response).to have_http_status(:success)
        body = response.parsed_body
        expect(body['periods']).to eq(%w[2026-10-01 2026-10-02])
        row = agent_row(body, seller)
        expect(row['periods']['2026-10-01']).to eq(
          'conversations_attended' => 1, 'messages_sent' => 2, 'assignments' => 0,
          'first_response_median' => 90, 'windows_closed' => 0, 'sales' => 1
        )
        expect(row['periods']['2026-10-02']).to eq(
          'conversations_attended' => 1, 'messages_sent' => 1, 'assignments' => 1,
          'first_response_median' => nil, 'windows_closed' => 1, 'sales' => 0
        )
        expect(row['totals']).to include('conversations_attended' => 2, 'messages_sent' => 3)
        expect(body['totals']).to include('conversations_attended' => 2, 'sales' => 1)
        expect(agent_row(body, administrator)['totals']).to include('messages_sent' => 0, 'first_response_median' => nil)
      end

      it 'groups by week starting on Monday' do
        get url, headers: administrator.create_new_auth_token, params: params.merge(group_by: 'week')

        body = response.parsed_body
        expect(body['periods']).to eq(['2026-09-28'])
        expect(agent_row(body, seller)['periods']['2026-09-28']).to include('conversations_attended' => 2, 'messages_sent' => 3)
      end

      it 'filters by inbox' do
        get url, headers: administrator.create_new_auth_token, params: params.merge(inbox_ids: [create(:inbox, account: account).id])

        expect(agent_row(response.parsed_body, seller)['totals']['messages_sent']).to eq(0)
      end

      it 'lists the conversations behind a metric' do
        get "#{url}/conversations", headers: administrator.create_new_auth_token,
                                    params: { since: '2026-10-01', until: '2026-10-01', user_ids: [seller.id], metric: 'conversations_attended' }

        expect(response).to have_http_status(:success)
        body = response.parsed_body
        expect(body['count']).to eq(1)
        expect(body['conversations'].first).to include('display_id' => conversation.display_id)
        expect(body['conversations'].first['last_message']).to include('message_type' => 'outgoing')
      end

      it 'rejects an unknown drill-down metric' do
        get "#{url}/conversations", headers: administrator.create_new_auth_token, params: params.merge(metric: 'resolved')

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'exports the report as CSV' do
        get "#{url}/export", headers: administrator.create_new_auth_token, params: params

        expect(response).to have_http_status(:success)
        expect(response.headers['Content-Type']).to include('text/csv')
        lines = response.body.lines.map(&:strip)
        expect(lines).to include("#{seller.available_name},2026-10-01,1,2,0,90,0,1")
        expect(lines).to include("#{seller.available_name},Total,2,3,1,90,1,1")
      end
    end

    context 'when the user is an agent' do
      it 'only returns their own activity when agents_see_only_own is on' do
        get url, headers: seller.create_new_auth_token, params: params.merge(user_ids: [other_seller.id])

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['agents'].pluck('id')).to eq([seller.id])
      end

      it 'returns every agent when agents_see_only_own is off' do
        Arroyo::Setting.for(account).tap { |setting| setting.merge_config(agent_panel: { agents_see_only_own: false }) }.save!
        other_seller

        get url, headers: seller.create_new_auth_token, params: params

        expect(response.parsed_body['agents'].pluck('id')).to include(seller.id, other_seller.id)
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/arroyo/agent_panel/windows' do
    let(:whatsapp_inbox) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox }
    let(:now) { argentina.parse('2026-10-03 12:00') }

    it 'lists WhatsApp windows closing soon and closed today' do
      closing = create(:conversation, account: account, inbox: whatsapp_inbox, assignee: seller)
      closed = create(:conversation, account: account, inbox: whatsapp_inbox, assignee: other_seller)
      open_window = create(:conversation, account: account, inbox: whatsapp_inbox, assignee: seller)
      other_channel = create(:conversation, account: account, inbox: inbox, assignee: seller)
      create(:message, account: account, conversation: closing, inbox: whatsapp_inbox, created_at: now - 20.hours)
      create(:message, account: account, conversation: closed, inbox: whatsapp_inbox, created_at: now - 30.hours)
      create(:message, account: account, conversation: open_window, inbox: whatsapp_inbox, created_at: now - 2.hours)
      create(:message, account: account, conversation: other_channel, inbox: inbox, created_at: now - 20.hours)

      travel_to(now) { get "#{url}/windows", headers: administrator.create_new_auth_token }

      body = response.parsed_body
      expect(body['closing_soon'].pluck('id')).to eq([closing.id])
      expect(body['closing_soon'].first['closes_at']).to eq((now + 4.hours).to_i)
      expect(body['closed_today'].pluck('id')).to eq([closed.id])
    end

    it 'only shows the agent their own conversations' do
      mine = create(:conversation, account: account, inbox: whatsapp_inbox, assignee: seller)
      theirs = create(:conversation, account: account, inbox: whatsapp_inbox, assignee: other_seller)
      [mine, theirs].each { |item| create(:message, account: account, conversation: item, inbox: whatsapp_inbox, created_at: now - 20.hours) }

      travel_to(now) { get "#{url}/windows", headers: seller.create_new_auth_token }

      expect(response.parsed_body['closing_soon'].pluck('id')).to eq([mine.id])
    end
  end
end
