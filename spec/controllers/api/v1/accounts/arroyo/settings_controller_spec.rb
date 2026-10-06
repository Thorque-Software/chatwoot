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
    it 'returns unauthorized for agents' do
      patch url, headers: agent.create_new_auth_token, params: { config: { window_keeper: { enabled: true } } }, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(Arroyo::Setting.count).to eq(0)
    end

    it 'merges the changes over the current config' do
      patch url,
            headers: administrator.create_new_auth_token,
            params: { config: { window_keeper: { enabled: true, nudge_buttons: ['Dale'], reengagement_template: nil },
                                post_sale: { stages: { d7: { days: 8 } } } } },
            as: :json

      expect(response).to have_http_status(:success)
      config = response.parsed_body['config']
      expect(config['window_keeper']).to include('enabled' => true, 'nudge_buttons' => ['Dale'], 'nudge_after_hours' => 22)
      expect(config['post_sale']['stages']['d7']).to include('days' => 8, 'template' => 'postventa_d7')
      expect(Arroyo::Setting.for(account).feature_enabled?(:window_keeper)).to be(true)
    end

    it 'drops keys outside the documented config' do
      patch url,
            headers: administrator.create_new_auth_token,
            params: { config: { window_keeper: { enabled: true, extra: 1 }, unknown: { enabled: true } } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(Arroyo::Setting.for(account)[:config]).to eq('window_keeper' => { 'enabled' => true })
    end

    it 'returns unprocessable entity for invalid values' do
      patch url,
            headers: administrator.create_new_auth_token,
            params: { config: { window_keeper: { nudge_buttons: %w[a b c d] } } },
            as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['errors']).to eq(['Invalid value for window_keeper.nudge_buttons'])
      expect(Arroyo::Setting.count).to eq(0)
    end
  end
end
