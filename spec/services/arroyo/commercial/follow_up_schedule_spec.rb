require 'rails_helper'

RSpec.describe Arroyo::Commercial::FollowUpSchedule do
  let(:account) { create(:account) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:conversation) { create(:conversation, account: account, inbox: channel.inbox, assignee: seller) }
  let(:zone) { ActiveSupport::TimeZone['America/Argentina/Buenos_Aires'] }

  before do
    setting = Arroyo::Setting.for(account)
    setting.merge_config(agent_panel: { enabled: true, funnel_enabled: true, seller_ids: [seller.id] })
    setting.save!
  end

  def incoming(at)
    travel_to(zone.parse(at)) { create(:message, account: account, conversation: conversation, message_type: :incoming) }
  end

  def schedule
    Arroyo::Commercial::FollowUpSchedule.new(opportunity: Arroyo::Opportunity.find_by!(conversation: conversation))
  end

  it 'enrolls a new contact without human attention or a manually added label, for the following day at ten' do
    incoming('2026-10-20 18:30')
    expect(conversation.reload.label_list).to include('seguimiento')
    expect(schedule.next_at).to eq(zone.parse('2026-10-21 10:00'))
    travel_to(zone.parse('2026-10-20 19:00')) { expect(schedule.due?).to be(false) }
    travel_to(zone.parse('2026-10-21 10:00')) { expect(schedule.due?).to be(true) }
  end

  it 'enrolls a historical conversation when seguimiento is added without inventing human attention' do
    setting = Arroyo::Setting.for(account)
    setting.merge_config(agent_panel: { funnel_enabled: false })
    setting.save!
    incoming('2026-10-10 09:00')
    setting.merge_config(agent_panel: { funnel_enabled: true })
    setting.save!
    travel_to(zone.parse('2026-10-20 18:00')) { conversation.reload.update!(label_list: ['seguimiento']) }
    expect(schedule.next_at).to eq(zone.parse('2026-10-21 10:00'))
    opportunity = Arroyo::Opportunity.find_by!(conversation: conversation)
    expect(opportunity.started_at).to eq(zone.parse('2026-10-10 09:00'))
    expect(opportunity.first_human_at).to be_nil
    expect(opportunity.coverage).to eq('partial')
  end

  it 'keeps the calendar when either the seller or the client writes again' do
    incoming('2026-10-20 09:00')
    travel_to(zone.parse('2026-10-21 09:03')) do
      conversation.reload
      create(:message, account: account, conversation: conversation, message_type: :outgoing, sender: seller)
      create(:message, account: account, conversation: conversation, message_type: :incoming)
    end
    travel_to(zone.parse('2026-10-21 10:00')) { expect(schedule.due?).to be(true) }
    expect(schedule.next_at).to eq(zone.parse('2026-10-21 10:00'))
  end

  it 'remembers manual cancellation despite subsequent incoming messages' do
    incoming('2026-10-20 09:00')
    travel_to(zone.parse('2026-10-20 18:00')) { conversation.reload.update!(label_list: []) }
    incoming('2026-10-21 09:00')
    expect(conversation.reload.label_list).not_to include('seguimiento')
    travel_to(zone.parse('2026-10-21 10:00')) { expect(schedule.due?).to be(false) }
  end

  it 'does not restart enrollment when unrelated labels change' do
    incoming('2026-10-20 09:00')
    travel_to(zone.parse('2026-10-21 09:00')) { conversation.reload.update!(label_list: %w[seguimiento bici]) }
    expect(schedule.next_at).to eq(zone.parse('2026-10-21 10:00'))
  end

  it 'moves Sunday to Monday' do
    incoming('2026-10-24 09:00')
    expect(schedule.next_at).to eq(zone.parse('2026-10-26 10:00'))
  end

  it 'does not recover a missed first date by sending it on a later day' do
    incoming('2026-10-19 09:00')
    travel_to(zone.parse('2026-10-21 10:00')) { expect(schedule.due?).to be(false) }
  end

  it 'starts the next day when a cancelled conversation is explicitly enrolled again' do
    incoming('2026-10-19 09:00')
    travel_to(zone.parse('2026-10-19 18:00')) { conversation.reload.update!(label_list: []) }
    travel_to(zone.parse('2026-10-20 18:00')) { conversation.reload.update!(label_list: ['seguimiento']) }
    expect(schedule.next_at).to eq(zone.parse('2026-10-21 10:00'))
  end

  it 'preserves legacy counters instead of repeating the first message for a historical chat' do
    setting = Arroyo::Setting.for(account)
    setting.merge_config(agent_panel: { funnel_enabled: false })
    setting.save!
    incoming('2026-10-10 09:00')
    conversation.reload.update!(custom_attributes: { seguimiento_envios: 2, seguimiento_ultimo_envio: '2026-10-19' })
    setting.merge_config(agent_panel: { funnel_enabled: true })
    setting.save!
    travel_to(zone.parse('2026-10-20 18:00')) { conversation.reload.update!(label_list: ['seguimiento']) }
    expect(schedule.sent_count).to eq(2)
    expect(schedule.next_at).to eq(zone.parse('2026-10-21 10:00'))
  end

  it 'does not turn a delayed old incoming update into automatic enrollment' do
    setting = Arroyo::Setting.for(account)
    setting.merge_config(agent_panel: { funnel_enabled: false })
    setting.save!
    message = incoming('2026-10-10 09:00')
    setting.merge_config(agent_panel: { funnel_enabled: true })
    setting.save!
    travel_to(zone.parse('2026-10-21 09:00')) { message.update!(content: 'Updated incoming') }
    expect(conversation.reload.label_list).not_to include('seguimiento')
  end

  it 'finishes atomically after three delivered stages without losing unrelated labels' do
    incoming('2026-10-14 09:00')
    opportunity = Arroyo::Opportunity.find_by!(conversation: conversation)
    travel_to(zone.parse('2026-10-14 09:30')) do
      create(:message, account: account, conversation: conversation.reload, message_type: :outgoing, sender: seller)
    end
    %w[15 17 19].each_with_index do |day, index|
      travel_to(zone.parse("2026-10-#{day} 10:00")) do
        create(:message, account: account, conversation: conversation.reload, message_type: :outgoing, status: :delivered,
                         content_attributes: { arroyo_kind: 'commercial_follow_up', arroyo_opportunity_reference: opportunity.reference,
                                               arroyo_step: index + 1 })
      end
    end
    conversation.reload.update!(label_list: %w[seguimiento bici cotizado])
    travel_to(zone.parse('2026-10-21 10:00')) do
      expect(schedule.complete).to be(true)
      expect(schedule.complete).to be(false)
    end
    expect(conversation.reload.label_list).to match_array(%w[bici cotizado inactivo])
  end

  it 'honors label removal on a historical chat that has never been enrolled' do
    setting = Arroyo::Setting.for(account)
    setting.merge_config(agent_panel: { funnel_enabled: false })
    setting.save!
    incoming('2026-10-10 09:00')
    conversation.reload.update!(label_list: ['seguimiento'])
    setting.merge_config(agent_panel: { funnel_enabled: true })
    setting.save!
    conversation.reload.update!(label_list: [])
    incoming('2026-10-20 09:00')
    expect(conversation.reload.label_list).not_to include('seguimiento')
  end

  it 'keeps legacy counters when a historical customer contacts again without an opportunity' do
    setting = Arroyo::Setting.for(account)
    setting.merge_config(agent_panel: { funnel_enabled: false })
    setting.save!
    incoming('2026-10-10 09:00')
    conversation.reload.update!(custom_attributes: { seguimiento_envios: 2, seguimiento_ultimo_envio: '2026-10-19' })
    setting.merge_config(agent_panel: { funnel_enabled: true })
    setting.save!
    incoming('2026-10-20 09:00')
    expect(schedule.sent_count).to eq(2)
  end

  it 'anchors concurrent incoming callbacks to the first contact date across midnight' do
    incoming('2026-10-20 23:59')
    opportunity = Arroyo::Opportunity.find_by!(conversation: conversation)
    opportunity.events.where(kind: 'follow_up_enrolled').delete_all
    travel_to(zone.parse('2026-10-21 00:01')) do
      create(:message, account: account, conversation: conversation.reload, message_type: :incoming)
    end
    expect(schedule.next_at).to eq(zone.parse('2026-10-21 10:00'))
  end

  it 'does not enroll a new opportunity from an older incoming callback' do
    original = incoming('2026-10-20 09:00')
    lifecycle = Arroyo::Commercial::Lifecycle.new(conversation: conversation)
    lifecycle.outcome(Arroyo::Opportunity.find_by!(conversation: conversation), outcome: 'won', user: seller)
    travel_to(zone.parse('2026-10-21 09:00')) do
      latest = lifecycle.start!(request_key: 'new-confirmed-intent', user: seller)
      Arroyo::Commercial::FollowUpEnrollment.new(conversation: conversation).automatic(original)
      expect(latest.events.where(kind: 'follow_up_enrolled')).not_to exist
    end
  end
end
