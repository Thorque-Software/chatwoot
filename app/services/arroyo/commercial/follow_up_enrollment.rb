class Arroyo::Commercial::FollowUpEnrollment
  attr_reader :conversation

  def initialize(conversation:)
    @conversation = Conversation.find(conversation.id)
  end

  def automatic(message)
    return unless message.incoming? && !message.private? && Arroyo::Commercial::Lifecycle.enabled?(conversation.account)

    conversation.with_lock do
      opportunity = current
      next if opportunity.nil? || message.created_at < opportunity.started_at

      Arroyo::Commercial::FollowUpSchedule.new(opportunity: opportunity).enroll(at: opportunity.started_at)
    end
  end

  def labels(change:, at:, actor:)
    added = Array(change.last) - Array(change.first)
    removed = Array(change.first) - Array(change.last)
    return unless (added | removed).include?('seguimiento')

    conversation.with_lock do
      opportunity = current
      if removed.include?('seguimiento')
        pause(at, opportunity, actor)
      else
        resume(at, opportunity, actor)
      end
    end
  end

  private

  def current
    Arroyo::Commercial::Lifecycle.new(conversation: conversation).current
  end

  def pause(at, opportunity, actor)
    conversation.update!(custom_attributes: conversation.custom_attributes.merge('arroyo_follow_up_stopped_at' => at.iso8601))
    Arroyo::Commercial::FollowUpSchedule.new(opportunity: opportunity).stop(at: at, actor: actor) if opportunity
  end

  def resume(at, opportunity, actor)
    if conversation.custom_attributes.key?('arroyo_follow_up_stopped_at')
      conversation.update!(custom_attributes: conversation.custom_attributes.except('arroyo_follow_up_stopped_at'))
    end
    opportunity ||= historical_opportunity(at)
    Arroyo::Commercial::FollowUpSchedule.new(opportunity: opportunity).enroll(at: at, manual: true, actor: actor) if opportunity
  end

  def historical_opportunity(at)
    trigger = Arroyo::Setting.for(conversation.account).section(:post_sale)['trigger_label']
    return if conversation.label_list.include?(trigger)

    opportunity = Arroyo::Opportunity.create!(account: conversation.account, conversation: conversation, contact: conversation.contact,
                                              inbox: conversation.inbox, assignee: conversation.assignee, reference: SecureRandom.uuid,
                                              started_at: historical_started_at(at), coverage: 'partial', state: 'unknown')
    opportunity.events.create!(kind: 'received', source_key: 'received', origin: 'backfill', occurred_at: opportunity.started_at)
    opportunity
  end

  def historical_started_at(fallback)
    conversation.messages.where(message_type: :incoming, private: false).minimum(:created_at) || fallback
  end
end
