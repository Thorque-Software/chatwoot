require 'rails_helper'

RSpec.describe Arroyo::Opportunity do
  it 'preserves native conversation and message deletion behavior' do
    account = create(:account)
    seller = create(:user, account: account, role: :administrator)
    setting = Arroyo::Setting.for(account)
    setting.merge_config(agent_panel: { funnel_enabled: true, seller_ids: [seller.id] })
    setting.save!
    conversation = create(:conversation, account: account, assignee: seller)
    incoming = create(:message, account: account, conversation: conversation, message_type: :incoming)
    expect { incoming.destroy! }.not_to raise_error
    expect { conversation.reload.destroy! }.not_to raise_error
    expect(described_class.where(conversation_id: conversation.id)).not_to exist
  end
end
