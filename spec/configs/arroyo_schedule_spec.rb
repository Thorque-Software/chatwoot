require 'rails_helper'

RSpec.describe 'Arroyo follow-up schedule' do
  let(:entry) { YAML.load_file(Rails.root.join('config/schedule.yml')).fetch('arroyo_commercial_follow_up_job') }

  it 'runs every day at 10:00 Argentina time' do
    next_run = Fugit::Cron.parse(entry['cron']).next_time(Time.utc(2026, 10, 23, 12, 0))

    expect(next_run.to_time.utc).to eq(Time.utc(2026, 10, 23, 13, 0))
  end

  it 'enqueues the follow-up job' do
    expect(entry['class'].constantize).to eq(Arroyo::Commercial::FollowUpJob)
  end
end
