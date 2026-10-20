require 'rails_helper'

RSpec.describe Arroyo::PostSale::MessageService do
  let(:account) { create(:account) }
  let(:seller) { create(:user, account: account, role: :administrator) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:conversation) { create(:conversation, account: account, inbox: channel.inbox, assignee: seller) }
  let(:zone) { ActiveSupport::TimeZone['America/Argentina/Buenos_Aires'] }

  before do
    channel.update!(message_templates: [{
                      'name' => 'postventa_d1', 'language' => 'es_AR', 'status' => 'APPROVED',
                      'category' => 'MARKETING', 'parameter_format' => 'NAMED',
                      'components' => [{ 'type' => 'BODY', 'text' => 'Hola, soy {{asesor}}. ¿Cómo va {{producto}}?' }]
                    }])
    setting = Arroyo::Setting.for(account)
    setting.merge_config(post_sale: { enabled: true, alert_user_ids: [seller.id] }, agent_panel: { enabled: true })
    setting.save!
  end

  def register_purchase
    conversation.update!(label_list: ['vendido'])
    Arroyo::PostSalePurchase.find_by!(conversation: conversation)
  end

  def schedule(purchase)
    stages = { d1: 1, d7: 7, d30: 30 }.transform_values do |days|
      (purchase.purchased_at.in_time_zone(zone).to_date + days).in_time_zone(zone).change(hour: 10).iso8601
    end
    Arroyo::PostSale::PlanService.new(purchase: purchase, revision: purchase.revision, stages: stages).perform
  end

  it 'captures the sale event, seller and three stages instead of the old conversation date' do
    conversation.update!(created_at: 2.months.ago)
    travel_to(zone.parse('2026-10-13 16:00')) do
      purchase = register_purchase

      expect(purchase.purchased_at).to eq(Time.current)
      expect(purchase.seller_id).to eq(seller.id)
      expect(purchase.follow_ups.pluck(:stage)).to match_array(%w[d1 d7 d30])
      schedule(purchase)
      expect(purchase.follow_ups.find_by!(stage: 'd7').scheduled_at).to eq(zone.parse('2026-10-20 10:00'))
    end
  end

  it 'does not invent another purchase when sold is removed and reapplied' do
    purchase = register_purchase
    conversation.update!(label_list: [])
    conversation.update!(label_list: ['vendido'])

    expect(Arroyo::PostSalePurchase.where(conversation: conversation).count).to eq(1)
    expect(purchase.follow_ups.reload).to all(have_attributes(status: 'cancelled'))
  end

  it 'creates exactly one system message for a stage and repeated HTTP-equivalent calls' do
    purchase = register_purchase
    schedule(purchase)
    follow_up = purchase.follow_ups.find_by!(stage: 'd1')
    conversation.resolved!
    travel_to(follow_up.scheduled_at) do
      create(:message, account: account, inbox: channel.inbox, conversation: conversation, message_type: :incoming)
      service = lambda {
        result = described_class.new(follow_up: follow_up, revision: purchase.revision,
                                     content: 'How is your product?', execution_id: 'fixture').perform
        expect(result.status).to eq('queued'), result.error_message
      }
      expect { 2.times { service.call } }.to change {
        conversation.messages.where(id: purchase.follow_ups.select(:message_id)).count
      }.by(1)
    end

    expect(follow_up.reload.message.sender).to be_nil
    expect(follow_up.message.content_attributes).to include('arroyo_kind' => 'post_sale', 'arroyo_stage' => 'd1')
    expect(conversation.reload).to be_open
    expect(follow_up.status).to eq('queued')
  end

  it 'records failure and a manual task when the approved template is unavailable' do
    channel.update!(message_templates: [])
    purchase = register_purchase
    schedule(purchase)
    follow_up = purchase.follow_ups.find_by!(stage: 'd1')
    travel_to(follow_up.scheduled_at) do
      described_class.new(follow_up: follow_up, revision: purchase.revision, content: 'Follow-up').perform
    end

    expect(follow_up.reload).to have_attributes(status: 'failed', error_code: 'template_unavailable', manual_status: 'pending',
                                                message_id: nil, alert_assignee_id: seller.id)
    expect(conversation.reload.label_list).to include('vendido', 'seguimiento-manual')
  end

  [true, false].each do |open_window|
    it "uses only the approved stage template with reply window open=#{open_window}" do
      purchase = register_purchase
      schedule(purchase)
      follow_up = purchase.follow_ups.find_by!(stage: 'd1')
      travel_to(follow_up.scheduled_at) do
        create(:message, account: account, inbox: channel.inbox, conversation: conversation, message_type: :incoming) if open_window
        expect(conversation.reload.can_reply?).to eq(open_window)
        described_class.new(follow_up: follow_up, revision: purchase.revision, content: 'Arbitrary editable text',
                            template_params: { 'name' => 'other_template' }).perform
      end
      expect(follow_up.reload).to have_attributes(status: 'queued', channel_used: 'template', template_name: 'postventa_d1')
      expect(follow_up.message.content).to eq("Hola, soy #{seller.available_name}. ¿Cómo va #{purchase.product}?")
      expect(follow_up.message.additional_attributes.dig('template_params', 'processed_params', 'body')).to eq(
        'asesor' => seller.available_name, 'producto' => purchase.product
      )
    end
  end

  it 'never falls back to text in an open window when a template is paused' do
    channel.update!(message_templates: channel.message_templates.map { |item| item.merge('status' => 'PAUSED') })
    purchase = register_purchase
    schedule(purchase)
    follow_up = purchase.follow_ups.find_by!(stage: 'd1')
    travel_to(follow_up.scheduled_at) do
      create(:message, account: account, inbox: channel.inbox, conversation: conversation, message_type: :incoming)
      expect(conversation.reload.can_reply?).to be(true)
      described_class.new(follow_up: follow_up, revision: purchase.revision, content: 'Do not send').perform
    end
    expect(follow_up.reload).to have_attributes(status: 'failed', message_id: nil, manual_status: 'pending')
  end

  it 'selects each stage template and retains the original seller when the conversation is reassigned' do
    templates = %w[d1 d7 d30].map { |stage| channel.message_templates.first.merge('name' => "postventa_#{stage}") }
    channel.update!(message_templates: templates)
    purchase = register_purchase
    schedule(purchase)
    conversation.update!(assignee: create(:user, account: account))
    purchase.follow_ups.each do |follow_up|
      travel_to(follow_up.scheduled_at) do
        described_class.new(follow_up: follow_up, revision: purchase.revision).perform
      end
      expect(follow_up.reload.template_name).to eq("postventa_#{follow_up.stage}")
      expect(follow_up.message.additional_attributes.dig('template_params', 'processed_params', 'body', 'asesor')).to eq(seller.available_name)
    end
  end

  it 'does not count initial sent as delivered and closes a pending alert on late delivery' do
    purchase = register_purchase
    follow_up = purchase.follow_ups.find_by!(stage: 'd1')
    message = create(:message, account: account, inbox: channel.inbox, conversation: conversation, message_type: :outgoing, sender: nil)
    follow_up.update!(message: message, status: 'queued', attempted_at: 7.hours.ago)

    Arroyo::PostSale::DeliveryService.new(follow_up: follow_up).perform
    expect(follow_up.reload.status).to eq('queued')
    Arroyo::PostSale::WatchdogJob.perform_now
    expect(follow_up.reload).to have_attributes(status: 'unconfirmed', manual_status: 'pending')
    alert_id = follow_up.alert_message_id

    message.update!(status: :delivered)
    2.times { Arroyo::PostSale::DeliveryService.new(follow_up: follow_up).perform }
    expect(follow_up.reload).to have_attributes(status: 'delivered', manual_status: 'closed_automatically', alert_message_id: alert_id)
  end

  it 'preserves a manual resolution when delivery arrives later' do
    purchase = register_purchase
    follow_up = purchase.follow_ups.find_by!(stage: 'd1')
    message = create(:message, account: account, inbox: channel.inbox, conversation: conversation, message_type: :outgoing, sender: nil)
    follow_up.update!(message: message, status: 'failed', error_message: 'Blocked')
    Arroyo::PostSale::AlertService.new(follow_up: follow_up).perform
    Arroyo::PostSale::ResolveService.new(follow_up: follow_up, user: seller, method: 'call', note: 'Contacted by phone').perform
    message.update!(status: :read)
    Arroyo::PostSale::DeliveryService.new(follow_up: follow_up).perform

    expect(follow_up.reload).to have_attributes(status: 'read', manual_status: 'resolved', resolution_method: 'call',
                                                resolution_note: 'Contacted by phone', error_message: 'Blocked')
  end

  it 'alerts for a scheduled stage that n8n never executed without claiming a Meta block' do
    purchase = register_purchase
    follow_up = purchase.follow_ups.find_by!(stage: 'd1')
    follow_up.update!(status: 'scheduled', scheduled_at: 7.hours.ago)
    2.times { Arroyo::PostSale::WatchdogJob.perform_now }

    expect(follow_up.reload).to have_attributes(status: 'not_executed', manual_status: 'pending', error_code: nil)
    expect(follow_up.alert_message_id).to be_present
  end

  it 'cancels pending stages when the contact is excluded and preserves unrelated attributes' do
    purchase = register_purchase
    schedule(purchase)
    conversation.contact.update!(label_list: ['no-contactar'])
    follow_up = purchase.follow_ups.find_by!(stage: 'd1')
    travel_to(follow_up.scheduled_at) do
      described_class.new(follow_up: follow_up, revision: purchase.revision, content: 'Follow-up').perform
    end
    expect(follow_up.reload).to have_attributes(status: 'cancelled', message_id: nil, manual_status: nil)

    conversation.update!(custom_attributes: { 'localidad' => 'Rosario', 'other_feature' => true })
    Arroyo::PostSale::AttributesService.new(conversation: conversation, attributes: { 'seguimiento_envios' => 2 }).perform
    expect(conversation.reload.custom_attributes).to include('localidad' => 'Rosario', 'other_feature' => true, 'seguimiento_envios' => 2)
  end

  it 'keeps attempted stages and alerts instead of sending corrected dates already in the past' do
    travel_to(zone.parse('2026-10-13 16:00')) do
      purchase = register_purchase
      attempted = purchase.follow_ups.find_by!(stage: 'd30')
      attempted.update!(status: 'failed', attempted_at: Time.current, error_message: 'Original failure')

      Arroyo::PostSale::CorrectDateService.new(purchase: purchase, purchased_at: '2026-10-01T16:00:00-03:00', user: seller).perform
      schedule(purchase)

      expect(purchase.follow_ups.where(stage: %w[d1 d7])).to all(have_attributes(status: 'not_executed', manual_status: 'pending'))
      expect(attempted.reload).to have_attributes(status: 'failed', error_message: 'Original failure', scheduled_at: nil)
      expect(purchase.reload.planned_revision).to eq(2)
    end
  end

  it 'does not replan an already accepted revision on a repeated request' do
    purchase = register_purchase
    schedule(purchase)
    before_dates = purchase.follow_ups.pluck(:stage, :scheduled_at)
    changed_dates = Arroyo::FollowUp::STAGES.index_with { 2.months.from_now.iso8601 }

    Arroyo::PostSale::PlanService.new(purchase: purchase, revision: purchase.revision, stages: changed_dates).perform

    expect(purchase.follow_ups.reload.pluck(:stage, :scheduled_at)).to eq(before_dates)
  end

  it 'closes manual tasks on exclusion while keeping failed delivery evidence' do
    purchase = register_purchase
    follow_up = purchase.follow_ups.find_by!(stage: 'd1')
    follow_up.update!(status: 'failed', attempted_at: Time.current, error_code: '131047', error_message: 'Closed window')
    Arroyo::PostSale::AlertService.new(follow_up: follow_up).perform
    conversation.contact.update!(label_list: ['no-contactar'])

    Arroyo::PostSale::WatchdogJob.perform_now

    expect(follow_up.reload).to have_attributes(status: 'failed', error_code: '131047', manual_status: 'closed_automatically')
    expect(conversation.reload.label_list).not_to include('seguimiento-manual')
    expect(purchase.reload.cancelled_at).to be_present
  end
end
