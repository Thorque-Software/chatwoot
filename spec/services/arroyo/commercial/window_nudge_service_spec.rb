require 'rails_helper'

RSpec.describe Arroyo::Commercial::WindowNudgeService do
  let(:zone) { ActiveSupport::TimeZone['America/Argentina/Buenos_Aires'] }
  let(:account) { create(:account) }
  let(:seller) { create(:user, account: account, role: :agent, name: 'Julieta Peralta', display_name: nil, email: 'juli@example.com') }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:contact) { create(:contact, account: account, name: 'Juan Carlos Sanchez') }
  let(:conversation) { create(:conversation, account: account, inbox: channel.inbox, contact: contact, assignee: seller) }
  let(:board) { { enabled: true, window_nudge: { enabled: true } } }

  before do
    setting = Arroyo::Setting.for(account)
    setting.merge_config(agent_panel: { enabled: true, funnel_enabled: true, seller_ids: [seller.id] }, funnel_board: board)
    setting.save!
    create(:message, account: account, inbox: channel.inbox, conversation: conversation, message_type: :incoming, sender: contact,
                     created_at: zone.parse('2026-11-10 15:00'))
    create(:message, account: account, inbox: channel.inbox, conversation: conversation, message_type: :outgoing, sender: seller,
                     created_at: zone.parse('2026-11-10 16:00'))
  end

  def opportunity
    Arroyo::Opportunity.find_by!(conversation: conversation)
  end

  def nudge(at = '2026-11-11 08:30')
    described_class.new(opportunity: opportunity, now: zone.parse(at)).perform
  end

  it 'sends one personalised reminder per window, marked as automatic' do
    expect(nudge('2026-11-11 08:15')).to be_nil

    message = nudge
    expect(message.content).to eq('Hola Juan, ¿pudiste ver lo que te pasamos? Si querés seguimos por acá 😊')
    expect(message.content_attributes).to include('arroyo_kind' => 'window_nudge', 'arroyo_opportunity_reference' => opportunity.reference)
    expect(opportunity.events.where(kind: 'window_nudge').count).to eq(1)
    expect(opportunity.last_human_at).to eq(zone.parse('2026-11-10 16:00'))
    expect(nudge('2026-11-11 09:00')).to be_nil
  end

  it 'drops the blank space when the contact has no name' do
    contact.update!(name: '')
    expect(nudge.content).to eq('Hola, ¿pudiste ver lo que te pasamos? Si querés seguimos por acá 😊')
  end

  it 'skips conversations with an excluded, sold or lost label' do
    %w[seguimiento vendido noquierenada].each do |label|
      conversation.update!(label_list: [label])
      expect(nudge).to be_nil
    end
  end

  it 'skips when the client wrote last' do
    create(:message, account: account, inbox: channel.inbox, conversation: conversation, message_type: :incoming, sender: contact,
                     created_at: zone.parse('2026-11-10 17:00'))
    expect(nudge).to be_nil
  end

  context 'when the reminder is off' do
    let(:board) { { enabled: true } }

    it 'sends nothing' do
      expect(nudge).to be_nil
    end
  end

  context 'when the panel shows only other numbers' do
    let(:board) { { enabled: true, inboxes: [{ id: create(:inbox, account: account).id, name: 'Otro' }], window_nudge: { enabled: true } } }

    it 'sends nothing' do
      expect(nudge).to be_nil
    end
  end
end
