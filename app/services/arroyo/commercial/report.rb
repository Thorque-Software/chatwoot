class Arroyo::Commercial::Report
  METRICS = %w[received bot unassigned pending assigned attended in_progress won lost inactive unknown overdue repeat_sales post_sale_replies
               post_sale_issues].freeze
  ACTIVITY = { 'received' => 'received', 'assigned' => 'assigned', 'human' => 'attended', 'won' => 'won' }.freeze
  attr_reader :query, :now

  def initialize(query:, now: Time.current)
    @query = query
    @now = now
  end

  def build
    metadata.merge(
      totals: totals(records), activity_totals: activity(events), coverage: coverage,
      series: filters.periods.map { |date| { date: date.iso8601, **activity(events_for(date)) } }, agents: agents
    )
  end

  def select(metric, scope: 'cohort')
    raise Arroyo::Commercial::Error, 'metric' unless (METRICS + ['assigned']).include?(metric)

    if scope == 'activity'
      kinds = ACTIVITY.select { |_key, value| value == metric }.keys
      ids = events.select { |event| kinds.include?(event.kind) }.map(&:opportunity_id).uniq
      return query.records(query.base.where(id: ids))
    end
    records.select { |record| matches?(record, metric) }
  end

  private

  def metadata
    {
      version: 2, timezone: filters.timezone.tzinfo.name, as_of: now.iso8601,
      since: filters.since_date.iso8601, until: filters.until_date.iso8601, group_by: filters.group_by
    }
  end

  def filters
    query.filters
  end

  def coverage
    { 'complete' => 0, 'partial' => 0 }.merge(records.group_by(&:coverage).transform_values(&:size))
  end

  def records
    @records ||= query.records
  end

  def events
    @events ||= query.events
  end

  def totals(items)
    METRICS.index_with { |metric| items.count { |item| matches?(item, metric) } }
  end

  def matches?(item, metric)
    case metric
    when 'received' then true
    when 'attended' then item.first_human_at.present?
    when 'assigned' then item.first_assignee_id.present?
    when 'overdue' then item.overdue?(now)
    else matches_result?(item, metric)
    end
  end

  def matches_result?(item, metric)
    case metric
    when 'repeat_sales' then repeat_sale_ids.include?(item.id)
    when 'post_sale_replies' then item.events.any? { |event| event.kind == 'post_sale_reply' }
    when 'post_sale_issues' then issue_opportunity_ids.include?(item.id)
    else item.effective_state(now) == metric
    end
  end

  def repeat_sale_ids
    @repeat_sale_ids ||= begin
      wins = Arroyo::Opportunity.where(account_id: filters.account.id, state: 'won').order(:outcome_at, :id).pluck(:id, :contact_id)
      seen = Set.new
      wins.filter_map { |id, contact| seen.add?(contact) ? nil : id }.to_set
    end
  end

  def issue_opportunity_ids
    @issue_opportunity_ids ||= issue_purchase_references.filter_map do |opportunity_id, conversation_id|
      opportunity_id || legacy_issue_opportunities[conversation_id]
    end.to_set
  end

  def issue_purchase_references
    @issue_purchase_references ||= Arroyo::FollowUp.joins(:purchase).where(account_id: filters.account.id)
                                                   .where(status: %w[failed not_executed unconfirmed])
                                                   .distinct.pluck('arroyo_post_sale_purchases.opportunity_id',
                                                                   'arroyo_post_sale_purchases.conversation_id')
  end

  def legacy_issue_opportunities
    @legacy_issue_opportunities ||= begin
      legacy_conversations = issue_purchase_references.filter_map { |opportunity_id, conversation_id| conversation_id unless opportunity_id }
      Arroyo::Opportunity.where(account: filters.account, conversation_id: legacy_conversations).group(:conversation_id).maximum(:id)
    end
  end

  def activity(items)
    ACTIVITY.values.index_with do |metric|
      kinds = ACTIVITY.select { |_key, value| value == metric }.keys
      items.select { |event| kinds.include?(event.kind) }.map(&:opportunity_id).uniq.size
    end
  end

  def event_user(event)
    case event.kind
    when 'assigned' then event.data['to']
    when 'won' then event.opportunity.result_user_id
    else event.actor_id
    end
  end

  def agents
    ids = filters.assignee_ids || filters.setting.section(:agent_panel)['seller_ids']
    filters.account.users.where(id: ids).order(:name).map { |user| agent_summary(user) }
  end

  def agent_summary(user)
    own_events = events_for_user(user)
    { id: user.id, name: user.available_name, totals: totals(records.select { |item| item.assignee_id == user.id }),
      periods: filters.periods.to_h { |date| [date.iso8601, activity(events_for(date, own_events))] } }
  end

  def events_for_user(user)
    events.select { |event| event_user(event) == user.id || (event.kind == 'received' && event.opportunity.assignee_id == user.id) }
  end

  def events_for(date, items = events)
    items.select do |event|
      local_date = event.occurred_at.in_time_zone(filters.timezone).to_date
      (filters.group_by == 'week' ? local_date.beginning_of_week(:monday) : local_date) == date
    end
  end
end
