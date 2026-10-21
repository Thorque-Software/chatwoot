class Arroyo::Commercial::Query
  attr_reader :filters

  def initialize(account_user:, params:)
    @filters = Arroyo::AgentPanel::Filters.new(account_user: account_user, params: params)
    @account_user = account_user
  end

  def base
    scope = Arroyo::Opportunity.where(account: @account_user.account)
    unless @account_user.administrator?
      inbox_ids = @account_user.user.inboxes.where(account: @account_user.account).select(:id)
      scope = scope.where(inbox_id: inbox_ids)
    end
    scope = scope.where(inbox_id: filters.inbox_ids) if filters.inbox_ids
    scope = scope.where(assignee_id: @account_user.user_id) if filters.only_own?
    scope
  end

  def owned
    filters.assignee_ids ? base.where(assignee_id: filters.assignee_ids) : base
  end

  def cohort
    owned.where(started_at: filters.time_range)
  end

  def records(scope = cohort)
    scope.includes(:account, :assignee, :result_user, :purchase, :contact,
                   { conversation: [:contact, :inbox, :assignee] }, { events: :message }).to_a
  end

  def events
    scope = Arroyo::OpportunityEvent.where(opportunity_id: base.select(:id), occurred_at: filters.time_range)
    scope.includes(:message, :opportunity).to_a.select do |event|
      next false if event.kind == 'human' && (!event.message || event.message.failed?)
      next true unless filters.assignee_ids

      filters.assignee_ids.include?(event_user_id(event))
    end
  end

  private

  def event_user_id(event)
    case event.kind
    when 'assigned' then event.data['to']
    when 'received' then event.opportunity.assignee_id
    when 'won' then event.opportunity.result_user_id
    else event.actor_id
    end
  end
end
