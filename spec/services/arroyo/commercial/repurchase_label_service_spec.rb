require 'rails_helper'

RSpec.describe Arroyo::Commercial::RepurchaseLabelService do
  let(:account) { create(:account) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:board_enabled) { true }

  before do
    setting = Arroyo::Setting.for(account)
    setting.merge_config(agent_panel: { enabled: true, funnel_enabled: true, seller_ids: [seller.id] },
                         funnel_board: { enabled: board_enabled })
    setting.save!
  end

  def sale(at)
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact, assignee: seller)
    travel_to(at) do
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact)
      lifecycle = Arroyo::Commercial::Lifecycle.new(conversation: conversation)
      lifecycle.outcome(lifecycle.current, outcome: 'won', user: seller)
    end
    conversation.reload
  end

  it 'labels the second purchase of a customer and keeps the sale label' do
    first = sale(10.days.ago)
    second = sale(1.day.ago)

    expect(first.label_list).to contain_exactly('vendido')
    expect(second.label_list).to contain_exactly('vendido', 'recompra')
    expect(account.labels.pluck(:title)).to include('recompra')
  end

  context 'when the panel funnel is off' do
    let(:board_enabled) { false }

    it 'leaves the labels alone' do
      sale(10.days.ago)
      expect(sale(1.day.ago).label_list).to contain_exactly('vendido')
    end
  end
end
