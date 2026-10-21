require 'rails_helper'

RSpec.describe Arroyo::Commercial::Lifecycle do
  let(:account) { create(:account) }
  let(:seller) { create(:user, account: account, role: :administrator) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:conversation) { create(:conversation, account: account, inbox: channel.inbox, assignee: seller) }
  let(:lifecycle) { described_class.new(conversation: conversation) }

  before do
    setting = Arroyo::Setting.for(account)
    setting.merge_config(agent_panel: { enabled: true, funnel_enabled: true, seller_ids: [seller.id] },
                         post_sale: { enabled: true, alert_user_ids: [seller.id] })
    setting.save!
    create(:message, account: account, conversation: conversation, message_type: :incoming)
  end

  it 'preserves the first purchase and creates three independent stages for the confirmed repeat sale' do
    first = lifecycle.current
    lifecycle.outcome(first, outcome: 'won', user: seller, product: 'Primera bicicleta')
    purchase = first.reload.purchase
    expect(purchase).to be_present
    original_reference = purchase.reference
    repeat = lifecycle.start!(request_key: 'repeat', user: seller, product: 'Segunda bicicleta')
    expect(purchase.reload.cancelled_at).to be_nil
    expect(purchase.follow_ups.pluck(:status, :cancellation_reason).uniq).to eq([%w[cancelled new_opportunity]])
    lifecycle.outcome(repeat, outcome: 'won', user: seller)
    expect(repeat.reload.purchase.reference).not_to eq(original_reference)
    expect(repeat.purchase.follow_ups.pluck(:stage)).to match_array(%w[d1 d7 d30])
    expect(Arroyo::PostSalePurchase.where(conversation: conversation).count).to eq(2)
  end

  it 'does not clear a newer opportunity attention or attribute an old referenced follow-up to it' do
    first = lifecycle.current
    lifecycle.outcome(first, outcome: 'won', user: seller)
    repeat = lifecycle.start!(request_key: 'repeat-2', user: seller)
    create(:message, account: account, conversation: conversation, message_type: :outgoing, sender: seller,
                     content_attributes: { arroyo_kind: 'commercial_follow_up', arroyo_opportunity_reference: first.reference })
    expect(repeat.events.where(kind: 'commercial_follow_up')).not_to exist
  end

  it 'does not turn a new opportunity into another sale when an unrelated label changes' do
    lifecycle.outcome(lifecycle.current, outcome: 'won', user: seller)
    repeat = lifecycle.start!(request_key: 'label-change', user: seller)
    conversation.reload.update!(label_list: conversation.label_list | ['bici'])
    expect(repeat.reload.state).not_to eq('won')
    expect(Arroyo::PostSalePurchase.where(conversation: conversation).count).to eq(1)
  end

  it 'routes an old human message status update to the original opportunity' do
    reply = conversation.messages.create!(account: account, inbox: channel.inbox, sender: seller, message_type: :outgoing, content: 'Te asesoro.')
    lifecycle.outcome(lifecycle.current, outcome: 'won', user: seller)
    repeat = lifecycle.start!(request_key: 'old-human-status', user: seller)
    reply.update!(status: :delivered)
    expect(repeat.reload.first_human_at).to be_nil
    expect(repeat.events.where(message: reply)).not_to exist
  end

  it 'keeps a manual alert label until all purchases in the conversation are resolved' do
    lifecycle.outcome(lifecycle.current, outcome: 'won', user: seller)
    first = lifecycle.current.purchase
    repeat = lifecycle.start!(request_key: 'pending-second-purchase', user: seller)
    lifecycle.outcome(repeat, outcome: 'won', user: seller)
    repeat.purchase.follow_ups.first.update!(manual_status: 'pending')
    conversation.reload.update!(label_list: conversation.label_list | ['seguimiento-manual'])
    first.follow_ups.each { |follow_up| follow_up.update!(manual_status: 'resolved') }
    Arroyo::PostSale::LabelService.clear_resolved(conversation)
    expect(conversation.reload.label_list).to include('seguimiento-manual')
  end

  it 'does not mark inactivity from failed sends or notes and resumes on incoming' do
    opportunity = lifecycle.current
    create(:message, account: account, conversation: conversation, message_type: :outgoing, sender: seller, created_at: 9.days.ago)
    3.times do |index|
      create(:message, account: account, conversation: conversation, message_type: :outgoing, sender: nil,
                       created_at: (7 - (2 * index)).days.ago,
                       content_attributes: { arroyo_kind: 'commercial_follow_up', arroyo_opportunity_reference: opportunity.reference,
                                             arroyo_step: index + 1 })
    end
    expect(opportunity.reload.effective_state).not_to eq('inactive') # the recent customer message still needs attention
  end
end
