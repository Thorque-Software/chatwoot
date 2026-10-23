require 'rails_helper'

RSpec.describe Arroyo::Commercial::FollowUpJob do
  let(:seller) { create(:user, account: enabled, role: :agent) }
  let(:enabled) { create(:account) }
  let(:disabled) { create(:account) }
  let(:service) { instance_double(Arroyo::Commercial::FollowUpDispatchService, perform: nil) }

  before do
    setting = Arroyo::Setting.for(enabled)
    setting.merge_config(agent_panel: { enabled: true, funnel_enabled: true, seller_ids: [seller.id] }, follow_up: { enabled: true })
    setting.save!
    Arroyo::Setting.for(disabled).save!
    allow(Arroyo::Commercial::FollowUpDispatchService).to receive(:new).and_return(service)
  end

  it 'runs only for accounts that turned the follow-ups on' do
    described_class.perform_now

    expect(Arroyo::Commercial::FollowUpDispatchService).to have_received(:new).once.with(account: enabled)
    expect(service).to have_received(:perform).once
  end
end
