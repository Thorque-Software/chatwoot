class Arroyo::AgentPanel::ReportBuilder
  METRICS = Arroyo::AgentPanel::Filters::METRICS.map(&:to_sym).freeze

  pattr_initialize [:filters!]

  def build
    collect_values
    {
      timezone: filters.timezone.tzinfo.name,
      since: filters.since_date.iso8601,
      until: filters.until_date.iso8601,
      group_by: filters.group_by,
      periods: filters.periods.map(&:iso8601),
      totals: metrics_for(nil, nil),
      agents: filters.users.map { |user| agent_row(user) }
    }
  end

  private

  def collect_values
    @values = Hash.new { |hash, key| hash[key] = {} }
    store(message_rows, :messages_sent, :conversations_attended)
    store(assignment_rows, :assignments)
    store(first_response_rows, :first_response_median)
    store(label_rows(Arroyo::WINDOW_CLOSED_LABEL), :windows_closed)
    store(label_rows(filters.sale_label), :sales)
  end

  def agent_row(user)
    {
      id: user.id,
      name: user.available_name,
      thumbnail: user.avatar_url,
      totals: metrics_for(user.id, nil),
      periods: filters.periods.to_h { |period| [period.iso8601, metrics_for(user.id, period)] }
    }
  end

  def metrics_for(user_id, period)
    values = @values[[user_id, period]]
    METRICS.index_with { |metric| values.fetch(metric) { metric == :first_response_median ? nil : 0 } }
  end

  def store(rows, *metrics)
    rows.each do |user_id, period, *values|
      @values[[user_id, period]].merge!(metrics.zip(values).to_h)
    end
  end

  def message_rows
    grouped(Arroyo::AgentPanel::Scopes.messages(filters), 'messages.sender_id', 'messages.created_at',
            'COUNT(*)', 'COUNT(DISTINCT messages.conversation_id)')
  end

  def assignment_rows
    grouped(Arroyo::AgentPanel::Scopes.assignments(filters), 'arroyo_assignment_events.assignee_id',
            'arroyo_assignment_events.created_at', 'COUNT(DISTINCT arroyo_assignment_events.conversation_id)')
  end

  def first_response_rows
    grouped(Arroyo::AgentPanel::Scopes.first_responses(filters), 'reporting_events.user_id', 'reporting_events.created_at',
            'ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY reporting_events.value))::integer')
  end

  def label_rows(label)
    grouped(Arroyo::AgentPanel::Scopes.label_taggings(filters, label), 'conversations.assignee_id', 'taggings.created_at',
            'COUNT(DISTINCT taggings.taggable_id)')
  end

  # Una sola consulta devuelve las filas por vendedor y período, el total por vendedor
  # (período nil) y el total general (vendedor y período nil)
  def grouped(scope, user_column, time_column, *aggregates)
    period = filters.period_sql(time_column)
    scope.group(Arel.sql("GROUPING SETS ((#{user_column}, #{period}), (#{user_column}), ())"))
         .pluck(Arel.sql(user_column), Arel.sql(period), *aggregates.map { |sql| Arel.sql(sql) })
  end
end
