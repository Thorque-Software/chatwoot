require 'rails_helper'

RSpec.describe Arroyo::Commercial::WindowNudgeJob do
  let(:account) { create(:account) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, assignee: seller) }

  def configure(nudge:)
    setting = Arroyo::Setting.for(account)
    setting.merge_config(agent_panel: { enabled: true, funnel_enabled: true, seller_ids: [seller.id] },
                         funnel_board: { enabled: true, window_nudge: { enabled: nudge } })
    setting.save!
  end

  it 'checks the open windows where the seller wrote last' do
    configure(nudge: true)
    waiting = create(:arroyo_opportunity, conversation: conversation, last_client_at: 3.hours.ago, last_human_at: 2.hours.ago)
    other = create(:conversation, account: account, assignee: seller)
    create(:arroyo_opportunity, conversation: other, last_client_at: 2.hours.ago, last_human_at: 3.hours.ago)
    service = instance_double(Arroyo::Commercial::WindowNudgeService, perform: nil)
    allow(Arroyo::Commercial::WindowNudgeService).to receive(:new).and_return(service)

    described_class.perform_now

    expect(Arroyo::Commercial::WindowNudgeService).to have_received(:new).once.with(opportunity: waiting, now: anything)
  end

  it 'does nothing while the reminder is off' do
    configure(nudge: false)
    create(:arroyo_opportunity, conversation: conversation, last_client_at: 3.hours.ago, last_human_at: 2.hours.ago)
    allow(Arroyo::Commercial::WindowNudgeService).to receive(:new)

    described_class.perform_now

    expect(Arroyo::Commercial::WindowNudgeService).not_to have_received(:new)
  end

  it 'is scheduled every 15 minutes' do
    entry = YAML.load_file(Rails.root.join('config/schedule.yml')).fetch('arroyo_window_nudge_job')
    expect(entry).to include('cron' => '*/15 * * * *', 'class' => described_class.name)
  end
end
