class Arroyo::Commercial::FollowUpMessageService
  pattr_initialize [:conversation!, :reference!, :step!, :immediate]

  def perform
    raise Arroyo::Commercial::Error, 'step' unless %w[1 2 3].include?(step.to_s)

    message = conversation.reload.with_lock { locked_message }
    raise Arroyo::Commercial::Error, 'delivery_failed' if message.failed?

    message
  end

  private

  def locked_message
    opportunity = Arroyo::Opportunity.find_by!(account: conversation.account, conversation: conversation, reference: reference)
    failed = opportunity.events.where(kind: 'commercial_follow_up').filter_map(&:message).find(&:failed?)
    if failed
      Arroyo::Commercial::FollowUpFailureService.new(opportunity: opportunity, message: failed).perform
      return failed
    end
    existing = opportunity.events.find_by(source_key: key)&.message
    existing || opportunity.with_lock { create_message(opportunity) }
  end

  def key
    "follow_up:#{step}"
  end

  def create_message(opportunity)
    validate_eligible(opportunity)
    payload = Arroyo::Commercial::TemplateService.new(opportunity: opportunity, step: step.to_i).perform
    raise Arroyo::Commercial::Error, 'template' unless payload

    message = Messages::MessageBuilder.new(nil, conversation, payload.merge(message_type: 'outgoing', private: false,
                                                                            content_attributes: attributes(opportunity))).perform
    opportunity.events.create!(kind: 'commercial_follow_up', source_key: key, origin: 'automation', occurred_at: message.created_at,
                               message: message, data: { arroyo_step: step.to_i })
    message
  end

  def validate_eligible(opportunity)
    latest = Arroyo::Commercial::Lifecycle.new(conversation: conversation).current
    raise Arroyo::Commercial::Error, 'not_eligible' unless latest.id == opportunity.id && eligible_opportunity?(opportunity)

    schedule = Arroyo::Commercial::FollowUpSchedule.new(opportunity: opportunity)
    raise Arroyo::Commercial::Error, 'step' unless step.to_i == schedule.sent_count + 1
    raise Arroyo::Commercial::Error, 'not_due' unless immediate || schedule.due?
  end

  def eligible_channel?
    conversation.inbox.channel_type == 'Channel::Whatsapp' && conversation.inbox.channel.provider == 'whatsapp_cloud'
  end

  def eligible_opportunity?(opportunity)
    Arroyo::Commercial::FollowUpSchedule.new(opportunity: opportunity).allowed? && eligible_channel? && contact_allowed?
  end

  def contact_allowed?
    labels = conversation.label_list + conversation.contact.label_list
    !conversation.contact.blocked? && !labels.intersect?(%w[no-contactar venta-cancelada venta-perdida])
  end

  def attributes(opportunity)
    { arroyo_kind: 'commercial_follow_up', arroyo_opportunity_reference: opportunity.reference, arroyo_step: step.to_i }
  end
end
