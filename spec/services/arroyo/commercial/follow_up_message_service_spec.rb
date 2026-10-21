require 'rails_helper'

RSpec.describe Arroyo::Commercial::FollowUpMessageService do
  let(:account) { create(:account) }
  let(:seller) { create(:user, account: account, role: :administrator) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:conversation) { create(:conversation, account: account, inbox: channel.inbox, assignee: seller) }

  before do
    setting = Arroyo::Setting.for(account)
    setting.merge_config(agent_panel: { enabled: true, funnel_enabled: true, seller_ids: [seller.id] })
    setting.save!
    channel.update!(message_templates: %w[seg_dia_1 seg_dia_3 seg_dia_5].map do |name|
      { name: name, language: 'es_AR', status: 'APPROVED', category: 'MARKETING', parameter_format: 'NAMED',
        components: [{ type: 'BODY', text: 'Soy {{asesor}}. ¿Seguimos con {{producto}}?' }] }
    end)
    create(:message, account: account, conversation: conversation, message_type: :incoming, created_at: 3.days.ago)
    create(:message, account: account, conversation: conversation, message_type: :outgoing, sender: seller, created_at: 2.days.ago)
  end

  def send_step(step)
    Arroyo::Commercial::FollowUpMessageService.new(conversation: conversation, reference: opportunity.reference, step: step).perform
  end

  def opportunity
    Arroyo::Opportunity.find_by!(conversation: conversation)
  end

  it 'creates one marked Meta template message for repeated same-step requests' do
    first = send_step(1)
    expect(send_step(1).id).to eq(first.id)
    expect(first.additional_attributes.dig('template_params', 'name')).to eq('seg_dia_1')
    expect(first.content_attributes).to include('arroyo_kind' => 'commercial_follow_up', 'arroyo_opportunity_reference' => opportunity.reference)
    expect(opportunity.reload.first_human_at).to be_present
    expect(opportunity.commercial_messages.size).to eq(1)
  end

  it 'does not skip steps or send before the two-day separation' do
    expect { send_step(2) }.to raise_error(Arroyo::Commercial::Error)
    send_step(1)
    expect { send_step(2) }.to raise_error(Arroyo::Commercial::Error)
  end

  it 'reports a failed existing step and leaves one private alert instead of returning a successful retry' do
    failed = send_step(1)
    failed.update!(status: :failed)
    2.times do
      expect { send_step(1) }.to raise_error(Arroyo::Commercial::Error) do |error|
        expect(error.code).to eq('delivery_failed')
      end
    end
    expect(opportunity.events.where(source_key: 'follow_up:1:failed').count).to eq(1)
    note = opportunity.events.find_by!(source_key: 'follow_up:1:failed').message
    expect(note).to be_private
    expect(note.content).to include(failed.id.to_s)
    expect(opportunity.events.where(kind: 'commercial_follow_up').pluck(:message_id).uniq).to eq([failed.id])
    expect(opportunity.commercial_messages).to be_empty
  end

  it 'detects a late failure from an earlier step without reporting a later successful step as a new send' do
    first = send_step(1)
    travel_to 2.days.from_now do
      second = send_step(2)
      first.update!(status: :failed)
      expect(opportunity.events.where(source_key: 'follow_up:1:failed').count).to eq(1)
      expect { send_step(2) }.to raise_error(Arroyo::Commercial::Error) do |error|
        expect(error.code).to eq('delivery_failed')
      end
      expect(opportunity.events.where(kind: 'commercial_follow_up_failure').count).to eq(1)
      expect(opportunity.commercial_messages.map(&:id)).to eq([second.id])
    end
  end

  it 'never falls back to text if Meta template is missing' do
    channel.update!(message_templates: [])
    expect { send_step(1) }.to raise_error(Arroyo::Commercial::Error)
    expect(opportunity.commercial_messages).to be_empty
  end
end
