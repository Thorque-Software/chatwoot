require 'rails_helper'

RSpec.describe Arroyo::SettingPolicy, type: :policy do
  subject(:setting_policy) { described_class }

  let(:account) { create(:account) }
  let(:administrator) { create(:user, :administrator, account: account) }
  let(:agent) { create(:user, account: account) }
  let(:administrator_context) { { user: administrator, account: account, account_user: administrator.account_users.first } }
  let(:agent_context) { { user: agent, account: account, account_user: agent.account_users.first } }

  permissions :show?, :update? do
    it { expect(setting_policy).to permit(administrator_context, Arroyo::Setting) }
    it { expect(setting_policy).not_to permit(agent_context, Arroyo::Setting) }
  end
end
