require 'rails_helper'

RSpec.describe Arroyo::Commercial::Lifecycle do
  let(:account) { create(:account) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:other) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: seller) }
  let(:service) { described_class.new(conversation: conversation) }

  before do
    setting = Arroyo::Setting.for(account)
    setting.merge_config(agent_panel: { enabled: true, funnel_enabled: true, seller_ids: [seller.id, other.id] })
    setting.save!
  end

  def message(type, sender: conversation.contact, **attributes)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: type, sender: sender, **attributes)
  end

  it 'records one opportunity and idempotent message events' do
    incoming = message(:incoming)
    2.times { service.message(incoming) }
    expect(Arroyo::Opportunity.where(conversation: conversation).count).to eq(1)
    expect(Arroyo::OpportunityEvent.where(source_key: "message:#{incoming.id}").count).to eq(1)
  end

  it 'does not count automated User messages or notes as human attention' do
    message(:incoming)
    automatic = message(:outgoing, sender: seller, content_attributes: { arroyo_kind: 'bot_handoff' })
    service.message(automatic)
    service.message(message(:outgoing, sender: seller, private: true))
    opportunity = Arroyo::Opportunity.find_by!(conversation: conversation)
    expect(opportunity.first_human_at).to be_nil
    expect(opportunity.pending_since).to be_present
    service.message(message(:outgoing, sender: seller))
    expect(opportunity.reload.first_human_at).to be_present
    expect(opportunity.pending_since).to be_nil
  end

  it 'keeps the first pending request across incoming messages and reassignment' do
    message(:incoming)
    opportunity = Arroyo::Opportunity.find_by!(conversation: conversation)
    pending = opportunity.pending_since
    due = opportunity.attention_due_at
    service.message(message(:incoming, created_at: 1.minute.from_now))
    conversation.update!(assignee: other)
    expect(opportunity.reload.pending_since).to eq(pending)
    expect(opportunity.attention_due_at).to eq(due)
    expect(opportunity.assignee_id).to eq(other.id)
  end

  it 'freezes the sale owner after transfer and a repeated win' do
    message(:incoming)
    opportunity = Arroyo::Opportunity.find_by!(conversation: conversation)
    service.outcome(opportunity, outcome: 'won', user: seller)
    conversation.update!(assignee: other)
    service.outcome(opportunity.reload, outcome: 'won', user: other)
    expect(opportunity.reload.result_user_id).to eq(seller.id)
    expect(opportunity.assignee_id).to eq(seller.id)
    expect(opportunity.events.where(kind: 'won').count).to eq(1)
  end

  it 'requires confirmation for another opportunity and deduplicates the request' do
    message(:incoming)
    original = Arroyo::Opportunity.find_by!(conversation: conversation)
    service.outcome(original, outcome: 'won', user: seller)
    service.message(message(:incoming))
    expect(Arroyo::Opportunity.where(conversation: conversation).count).to eq(1)
    one = service.start!(request_key: 'confirmed-repeat', user: other)
    two = service.start!(request_key: 'confirmed-repeat', user: other)
    expect(one).to eq(two)
    expect(one.id).not_to eq(original.id)
    expect(original.reload.state).to eq('won')
  end

  it 'restores pending human attention if the reply later fails' do
    message(:incoming)
    reply = message(:outgoing, sender: seller)
    service.message(reply)
    expect(Arroyo::Opportunity.find_by!(conversation: conversation).pending_since).to be_nil
    reply.update!(status: :failed)
    service.message(reply)
    expect(Arroyo::Opportunity.find_by!(conversation: conversation).pending_since).to be_present
  end

  describe 'panel funnel' do
    def enable_board
      setting = Arroyo::Setting.for(account)
      setting.merge_config(funnel_board: { enabled: true })
      setting.save!
    end

    it 'marks the inquiry lost with the configured label only when the panel funnel is on' do
      message(:incoming)
      opportunity = Arroyo::Opportunity.find_by!(conversation: conversation)
      service.labels(actor: seller, change: [[], ['noquierenada']])
      expect(opportunity.reload.state).to eq('pending')

      enable_board
      service.labels(actor: seller, change: [[], ['noquierenada']])
      expect(opportunity.reload).to have_attributes(state: 'lost', result_user_id: seller.id)
    end

    it 'still accepts the historical venta-perdida label' do
      message(:incoming)
      service.labels(actor: seller, change: [[], ['venta-perdida']])
      expect(Arroyo::Opportunity.find_by!(conversation: conversation).state).to eq('lost')
    end

    it 'stores the Meta ad that opened the inquiry' do
      conversation.update!(additional_attributes: { 'ad_id' => '52615', 'ad_name' => 'Reel Bici', 'ad_referral_at' => Time.current.iso8601 })
      message(:incoming)
      expect(Arroyo::Opportunity.find_by!(conversation: conversation).origin).to eq('ad_id' => '52615', 'ad_name' => 'Reel Bici')
    end
  end

  it 'keeps all new recording disabled by default' do
    setting = Arroyo::Setting.for(account)
    setting.merge_config(agent_panel: { funnel_enabled: false })
    setting.save!
    message(:incoming)
    expect(Arroyo::Opportunity.where(account: account)).not_to exist
  end
end
