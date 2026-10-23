require 'rails_helper'

RSpec.describe Arroyo::Commercial::FollowUpDispatchService do
  let(:account) { create(:account) }
  let(:seller) { create(:user, account: account, role: :administrator) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:zone) { ActiveSupport::TimeZone['America/Argentina/Buenos_Aires'] }
  let(:templates) do
    %w[seg_dia_1 seg_dia_3 seg_dia_5].map do |name|
      { name: name, language: 'es_AR', status: 'APPROVED', category: 'MARKETING', parameter_format: 'NAMED',
        components: [{ type: 'BODY', text: 'Soy {{asesor}}. ¿Seguimos con {{producto}}?' }] }
    end
  end

  before do
    setting = Arroyo::Setting.for(account)
    setting.merge_config(agent_panel: { enabled: true, funnel_enabled: true, seller_ids: [seller.id] }, follow_up: { enabled: true })
    setting.save!
    channel.update!(message_templates: templates)
  end

  def enrolled_conversation(inbox, at)
    conversation = create(:conversation, account: account, inbox: inbox, assignee: seller)
    travel_to(zone.parse(at)) do
      create(:message, account: account, conversation: conversation, message_type: :incoming)
      conversation.reload.update!(label_list: ['seguimiento'])
    end
    conversation
  end

  def sent(conversation)
    Arroyo::Opportunity.find_by!(conversation: conversation).commercial_messages.size
  end

  it 'sends the due step once and leaves later enrollments for their own day' do
    due = enrolled_conversation(channel.inbox, '2026-10-20 10:00')
    later = enrolled_conversation(channel.inbox, '2026-10-21 09:00')
    travel_to(zone.parse('2026-10-21 10:00')) do
      described_class.new(account: account).perform
      described_class.new(account: account).perform
    end
    expect(sent(due)).to eq(1)
    expect(sent(later)).to eq(0)
  end

  it 'keeps sending to the others when one chat cannot be sent' do
    broken_channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
    broken = enrolled_conversation(broken_channel.inbox, '2026-10-20 10:00')
    working = enrolled_conversation(channel.inbox, '2026-10-20 10:00')
    travel_to(zone.parse('2026-10-21 10:00')) { described_class.new(account: account).perform }
    expect(sent(broken)).to eq(0)
    expect(sent(working)).to eq(1)
  end

  it 'closes a finished sequence and keeps the other labels' do
    conversation = enrolled_conversation(channel.inbox, '2026-10-14 09:00')
    opportunity = Arroyo::Opportunity.find_by!(conversation: conversation)
    %w[15 17 19].each_with_index do |day, index|
      travel_to(zone.parse("2026-10-#{day} 10:00")) do
        create(:message, account: account, conversation: conversation.reload, message_type: :outgoing, status: :delivered,
                         content_attributes: { arroyo_kind: 'commercial_follow_up', arroyo_opportunity_reference: opportunity.reference,
                                               arroyo_step: index + 1 })
      end
    end
    conversation.reload.update!(label_list: %w[seguimiento bici])
    travel_to(zone.parse('2026-10-21 10:00')) { described_class.new(account: account).perform }
    expect(conversation.reload.label_list).to eq(['bici'])
  end
end
