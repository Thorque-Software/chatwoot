require 'rails_helper'

RSpec.describe Arroyo::Commercial::AssignmentService do
  let(:account) { create(:account) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:other) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }

  before do
    setting = Arroyo::Setting.for(account)
    setting.merge_config(agent_panel: { enabled: true, funnel_enabled: true, balanced_assignment_enabled: true,
                                        seller_ids: [seller.id, other.id] })
    setting.save!
    [seller, other].each { |user| create(:inbox_member, inbox: inbox, user: user) }
  end

  it 'counts a new assignment before the after-commit listener has projected it' do
    # Emulates the interval after the account lock is released but before its callback runs.
    allow(Arroyo::CommercialListener.instance).to receive(:assignee_changed)
    conversations = Array.new(2) do
      conversation = create(:conversation, account: account, inbox: inbox, assignee: nil)
      create(:message, account: account, conversation: conversation, message_type: :incoming)
      conversation
    end
    assigned = conversations.map { |conversation| described_class.new(conversation: conversation).perform[:assignee_id] }
    expect(assigned).to contain_exactly(seller.id, other.id)
    expect(Arroyo::Opportunity.where(conversation: conversations).pluck(:assignee_id)).to match_array(assigned)
  end
end
