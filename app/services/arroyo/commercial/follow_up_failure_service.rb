class Arroyo::Commercial::FollowUpFailureService
  pattr_initialize [:opportunity!, :message!]

  def perform
    return unless message.failed? && message.content_attributes['arroyo_kind'] == 'commercial_follow_up'

    opportunity.with_lock do
      next if opportunity.events.exists?(source_key: key)

      note = Messages::MessageBuilder.new(nil, opportunity.conversation, payload).perform
      opportunity.events.create!(kind: 'commercial_follow_up_failure', source_key: key, origin: 'automation',
                                 occurred_at: Time.current, message: note, data: { failed_message_id: message.id, arroyo_step: step })
    end
  end

  private

  def step
    message.content_attributes['arroyo_step'].to_i
  end

  def key
    "follow_up:#{step}:failed"
  end

  def payload
    { content: I18n.t('arroyo.commercial.follow_up_failed_note', step: step, message: message.id),
      message_type: 'outgoing', private: true,
      content_attributes: { arroyo_kind: 'commercial_follow_up_failure', arroyo_opportunity_reference: opportunity.reference } }
  end
end
