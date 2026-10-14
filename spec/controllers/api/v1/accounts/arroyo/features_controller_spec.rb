require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Arroyo::FeaturesController', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }

  describe 'GET /api/v1/accounts/{account.id}/arroyo/features' do
    it 'returns the panel flags to any user of the account' do
      get "/api/v1/accounts/#{account.id}/arroyo/features", headers: agent.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to eq(
        'timezone' => 'America/Argentina/Buenos_Aires',
        'agent_panel' => { 'enabled' => false, 'agents_see_only_own' => true, 'hide_native_reports' => false },
        'social_comments' => { 'enabled' => false, 'inboxes' => [] },
        'post_sale' => { 'enabled' => false, 'has_records' => false }
      )
    end

    it 'returns unauthorized for users of another account' do
      get "/api/v1/accounts/#{account.id}/arroyo/features", headers: create(:user).create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
