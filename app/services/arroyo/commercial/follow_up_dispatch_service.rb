class Arroyo::Commercial::FollowUpDispatchService
  pattr_initialize [:account!]

  def perform
    latest_opportunities.each do |opportunity|
      dispatch(opportunity)
    rescue StandardError => e
      ChatwootExceptionTracker.new(e, account: account).capture_exception
    end
  end

  private

  def dispatch(opportunity)
    schedule = Arroyo::Commercial::FollowUpSchedule.new(opportunity: opportunity)
    return schedule.complete if schedule.finish_due?
    return unless schedule.due?

    Arroyo::Commercial::FollowUpMessageService.new(conversation: opportunity.conversation, reference: opportunity.reference,
                                                   step: schedule.sent_count + 1).perform
  end

  def latest_opportunities
    scope = Arroyo::Opportunity.where(account: account)
    scope.where(id: scope.select('MAX(arroyo_opportunities.id)').group(:conversation_id))
         .includes(:account, :assignee, :contact, :inbox, conversation: :contact, events: :message)
  end
end
