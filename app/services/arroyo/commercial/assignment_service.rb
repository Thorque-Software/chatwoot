class Arroyo::Commercial::AssignmentService
  pattr_initialize [:conversation!]

  def perform
    previous_actor = Current.executed_by
    Current.executed_by = conversation.account
    conversation.account.with_lock do
      conversation.reload.with_lock { assign_locked }
    end
  ensure
    Current.executed_by = previous_actor
  end

  private

  def assign_locked
    lifecycle = Arroyo::Commercial::Lifecycle.new(conversation: conversation)
    opportunity = lifecycle.current || lifecycle.start!(request_key: "initial:#{conversation.id}", user: nil)
    return result(opportunity, false) if conversation.assignee_id

    raise Arroyo::Commercial::Error, 'superseded' if opportunity.terminal?

    assignee = choose_agent
    Conversations::AssignmentService.new(conversation: conversation, assignee_id: assignee.id).perform
    # Publish the balance before releasing the account lock; the native callback records the event after commit.
    opportunity.update!(assignee: assignee, first_assignee_id: opportunity.first_assignee_id || assignee.id,
                        ownership_started_at: conversation.updated_at)
    result(opportunity.reload, true)
  end

  def config
    Arroyo::Setting.for(conversation.account).section(:agent_panel)
  end

  def choose_agent
    agents = eligible_agents
    raise Arroyo::Commercial::Error, 'sellers' if agents.empty?

    scope = assignment_scope(agents)
    counts = scope.group(:assignee_id).count
    last = scope.group(:assignee_id).maximum(:ownership_started_at)
    agents.min_by { |user| [counts.fetch(user.id, 0), last[user.id] || Time.zone.at(0), user.id] }
  end

  def eligible_agents
    permitted = conversation.inbox.member_ids | conversation.account.administrators.pluck(:id)
    conversation.account.users.where(id: config['seller_ids'] & permitted).order(:id).to_a
  end

  def assignment_scope(agents)
    Arroyo::Opportunity.where(account: conversation.account, assignee_id: agents.map(&:id))
                       .where(ownership_started_at: config['lookback_days'].days.ago..Time.current)
  end

  def result(opportunity, assigned)
    { assignee_id: conversation.assignee_id, opportunity_reference: opportunity.reference, assigned: assigned }
  end
end
