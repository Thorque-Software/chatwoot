require 'rails_helper'

RSpec.describe Arroyo::Commercial::Abandonment do
  let(:account) { create(:account) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, assignee: seller) }
  let(:opportunity) { create(:arroyo_opportunity, conversation: conversation, started_at: 3.days.ago) }
  let(:board) { Arroyo::FunnelBoardConfig::DEFAULTS }

  def event(kind, at, message: nil)
    opportunity.events.create!(kind: kind, source_key: "#{kind}:#{at.to_f}", origin: 'system', occurred_at: at, message: message)
  end

  def abandoned?(now: Time.current, labels: [])
    described_class.new(board: board, now: now).abandoned?(opportunity.reload, labels)
  end

  it 'needs the window reminder' do
    expect(abandoned?).to be(false)
  end

  it 'is abandoned after the configured hours without a seller reply' do
    event('window_nudge', 30.hours.ago)
    expect(abandoned?(now: 30.hours.ago + 23.hours)).to be(false)
    expect(abandoned?).to be(true)
  end

  it 'stops being abandoned when the seller writes again or the chat is in follow-up' do
    event('window_nudge', 30.hours.ago)
    expect(abandoned?(labels: ['seguimiento'])).to be(false)

    reply = create(:message, account: account, conversation: conversation, message_type: :outgoing, sender: seller)
    event('human', 2.hours.ago, message: reply)
    expect(abandoned?).to be(false)
  end

  it 'does not count a failed seller reply' do
    event('window_nudge', 30.hours.ago)
    reply = create(:message, account: account, conversation: conversation, message_type: :outgoing, sender: seller, status: :failed)
    event('human', 2.hours.ago, message: reply)
    expect(abandoned?).to be(true)
  end

  it 'never applies to closed inquiries' do
    event('window_nudge', 30.hours.ago)
    opportunity.update!(state: 'won')
    expect(abandoned?).to be(false)
  end
end
