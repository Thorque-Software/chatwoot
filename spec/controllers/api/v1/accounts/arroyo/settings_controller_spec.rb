require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Arroyo::SettingsController', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/arroyo/settings" }

  describe 'GET /api/v1/accounts/{account.id}/arroyo/settings' do
    it 'returns unauthorized for unauthenticated users' do
      get url

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns unauthorized for agents' do
      get url, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns the defaults without creating a record' do
      get url, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['config']).to eq(Arroyo::Setting::DEFAULTS)
      expect(Arroyo::Setting.count).to eq(0)
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/arroyo/settings' do
    it 'ignores retired message editors and fixed template names' do
      patch url, headers: administrator.create_new_auth_token, as: :json,
                 params: { config: { post_sale: { stages: { d1: { free_text: 'Custom body', template: 'other' } } },
                                     window_keeper: { enabled: true, nudge_text: 'Custom reminder' } } }
      expect(response).to have_http_status(:success)
      config = response.parsed_body['config']
      expect(config.dig('post_sale', 'stages', 'd1')).to eq('days' => 1, 'template' => 'postventa_d1')
      expect(config.dig('window_keeper', 'enabled')).to be(false)
      expect(Arroyo::Setting.for(account)[:config].to_json).not_to include('Custom body', 'Custom reminder', 'other')
    end

    it 'returns unauthorized for agents' do
      patch url, headers: agent.create_new_auth_token, params: { config: { window_keeper: { enabled: true } } }, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(Arroyo::Setting.count).to eq(0)
    end

    it 'merges the changes over the current config' do
      patch url,
            headers: administrator.create_new_auth_token,
            params: { config: { agent_panel: { enabled: true },
                                post_sale: { stages: { d7: { days: 8 } } } } },
            as: :json

      expect(response).to have_http_status(:success)
      config = response.parsed_body['config']
      expect(config['agent_panel']).to include('enabled' => true)
      expect(config['post_sale']['stages']['d7']).to include('days' => 8, 'template' => 'postventa_d7')
      expect(Arroyo::Setting.for(account).feature_enabled?(:agent_panel)).to be(true)
    end

    it 'drops keys outside the documented config' do
      patch url,
            headers: administrator.create_new_auth_token,
            params: { config: { agent_panel: { enabled: true, extra: 1 }, unknown: { enabled: true } } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(Arroyo::Setting.for(account)[:config]).to eq('agent_panel' => { 'enabled' => true })
    end

    it 'returns unprocessable entity for invalid values' do
      patch url,
            headers: administrator.create_new_auth_token,
            params: { config: { post_sale: { send_hour_local: 26 } } },
            as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['errors']).to eq(['Invalid value for post_sale.send_hour_local'])
      expect(Arroyo::Setting.count).to eq(0)
    end
  end
end
