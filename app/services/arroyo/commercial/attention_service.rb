class Arroyo::Commercial::AttentionService
  def initialize(opportunity:)
    @opportunity = opportunity
  end

  def perform
    opportunity.update!(first_human_at: human.first&.occurred_at, last_human_at: last_human, last_client_at: incoming.last&.occurred_at,
                        pending_since: pending_since, attention_due_at: deadline, state: state)
  end

  private

  attr_reader :opportunity

  def events
    @events ||= opportunity.events.where(kind: %w[incoming human]).includes(:message).order(:occurred_at, :id).to_a
  end

  def human
    @human ||= events.select { |event| event.kind == 'human' && event.message && !event.message.failed? }
  end

  def incoming
    @incoming ||= events.select { |event| event.kind == 'incoming' }
  end

  def last_human
    human.last&.occurred_at
  end

  def pending_since
    return nil if opportunity.assignee_id.nil? && opportunity.first_assignee_id.nil?

    unanswered = incoming.find { |event| last_human.nil? || event.occurred_at > last_human }
    pending = unanswered&.occurred_at
    pending = initial_pending(pending) if human.empty?
    pending
  end

  def initial_pending(pending)
    first_assignment = opportunity.events.where(kind: 'assigned').minimum(:occurred_at) if pending
    pending = [pending, first_assignment].compact.max if pending
    pending || opportunity.pending_since
  end

  def deadline
    return unless pending_since

    setting = Arroyo::Setting.for(opportunity.account)
    zone = ActiveSupport::TimeZone[setting.config['timezone']]
    Arroyo::Commercial::BusinessCalendar.new(timezone: zone, hours: setting.section(:agent_panel)['response_hours']).deadline(pending_since)
  end

  def state
    return opportunity.state if opportunity.terminal?
    return 'in_progress' if human.any?
    return 'pending' if opportunity.assignee_id

    conversation = opportunity.conversation
    conversation.pending? || conversation.assignee_agent_bot_id ? 'bot' : 'unassigned'
  end
end
