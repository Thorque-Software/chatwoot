require 'rails_helper'

RSpec.describe Arroyo::Commercial::BackfillService do
  it 'imports only evidence, labels uncertain human history as partial and does not send or assign' do
    account = create(:account)
    seller = create(:user, account: account, role: :agent)
    conversation = create(:conversation, account: account, assignee: seller)
    create(:message, account: account, conversation: conversation, message_type: :incoming, created_at: 2.days.ago)
    create(:message, account: account, conversation: conversation, message_type: :outgoing, sender: seller, created_at: 1.day.ago)
    service = described_class.new(account: account)
    expect { 2.times { service.perform } }.not_to change(Message, :count)
    record = Arroyo::Opportunity.find_by!(conversation: conversation)
    expect(record.coverage).to eq('partial')
    expect(record.state).to eq('unknown')
    expect(record.first_human_at).to be_nil
    expect(conversation.reload.assignee_id).to eq(seller.id)
    expect(Arroyo::Opportunity.where(conversation: conversation).count).to eq(1)
  end
end
