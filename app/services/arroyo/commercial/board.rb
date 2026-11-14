# Embudo unificado del panel de vendedores (funnel_board): todas las consultas que llegaron en el período, de qué
# origen vinieron, a quién le tocan y en qué quedaron, por vendedor y por día. Todos los usuarios ven los números de
# todos; el detalle de cada consulta (select) respeta los permisos de siempre.
# Cohorte: consultas por fecha de llegada (started_at) en la zona horaria del negocio.
class Arroyo::Commercial::Board
  POST_SALE_ISSUES = %w[failed not_executed unconfirmed].freeze
  ISSUES_LIMIT = 50

  attr_reader :filters

  def initialize(account_user:, params:, now: Time.current)
    @account_user = account_user
    @account = account_user.account
    @params = params
    @now = now
    @filters = Arroyo::AgentPanel::Filters.new(account_user: account_user, params: params)
  end

  def valid?
    filters.valid?(:report) && Arroyo::Commercial::BoardOrigins::LEVELS.include?(level) && allowed_inboxes?
  end

  def errors
    filters.errors.full_messages.presence || ['Invalid value for inbox_ids or origin_level']
  end

  def build
    { version: 1, timezone: filters.timezone.tzinfo.name, as_of: @now.iso8601, since: filters.since_date.iso8601,
      until: filters.until_date.iso8601, origin_level: level, inboxes: inbox_options, totals: totals,
      flow: flow.build, info_labels: info_labels, sellers: sellers, days: days,
      origins: origins.table(rows), repurchases: repurchases, post_sale_issues: post_sale_issues }
  end

  # Consultas de un nodo o celda del panel (filas). filter: origin, bucket, stage, label, attended, metric, date.
  def select(filter)
    allowed = Arroyo::Commercial::Query.new(account_user: @account_user, params: {}).base.pluck(:id).to_set
    rows.select { |row| allowed.include?(row.record.id) && matches?(row, filter) }
  end

  def rows
    @rows ||= records.map do |record|
      Arroyo::Commercial::BoardRow.new(record, abandonment: abandonment, now: @now, timezone: filters.timezone)
    end
  end

  private

  def board
    @board ||= filters.setting.section(:funnel_board)
  end

  def level
    @params[:origin_level].presence || 'campaign'
  end

  def configured_inbox_ids
    board['inboxes'].pluck('id').presence
  end

  def inbox_ids
    filters.inbox_ids || configured_inbox_ids
  end

  def allowed_inboxes?
    filters.inbox_ids.nil? || configured_inbox_ids.nil? || (filters.inbox_ids - configured_inbox_ids).empty?
  end

  def inbox_options
    return board['inboxes'] if configured_inbox_ids

    @account.inboxes.order(:id).map { |inbox| { 'id' => inbox.id, 'name' => inbox.name } }
  end

  def records
    scope = Arroyo::Opportunity.where(account: @account, started_at: filters.time_range)
    scope = scope.where(inbox_id: inbox_ids) if inbox_ids
    scope = scope.where(assignee_id: @params[:user_ids].map(&:to_i)) if @params[:user_ids].present?
    scope.includes(:account, :assignee, :contact, { conversation: [:contact, :inbox, :assignee] }, { events: :message })
         .order(:started_at, :id).to_a
  end

  def abandonment
    @abandonment ||= Arroyo::Commercial::Abandonment.new(board: board, now: @now)
  end

  def origins
    @origins ||= Arroyo::Commercial::BoardOrigins.new(account: @account, records: rows.map(&:record))
  end

  def flow
    @flow ||= Arroyo::Commercial::BoardFlow.new(rows: rows, origins: origins, level: level, seller_names: seller_names)
  end

  def totals
    organic = rows.count { |row| organic?(row) }
    buckets = rows.map(&:bucket).tally
    Arroyo::Commercial::BoardRow.counts(rows).merge(
      'from_ads' => rows.size - organic, 'organic' => organic, 'bot' => buckets.fetch('bot', 0),
      'unassigned' => buckets.fetch('unassigned', 0), 'assigned' => rows.count(&:seller?), 'nudged' => rows.count(&:nudged?)
    )
  end

  def organic?(row)
    origins.key(row.record, 'ad') == Arroyo::Commercial::BoardOrigins::ORGANIC
  end

  def seller_ids
    configured = filters.setting.section(:agent_panel)['seller_ids']
    ids = (configured + rows.select(&:seller?).map { |row| row.record.assignee_id }).uniq
    @params[:user_ids].present? ? ids & @params[:user_ids].map(&:to_i) : ids
  end

  def seller_names
    @seller_names ||= @account.users.where(id: seller_ids).to_h { |user| [user.id.to_s, user.available_name] }
  end

  def sellers
    by_seller = rows.select(&:seller?).group_by(&:bucket)
    seller_names.map { |id, name| { 'id' => id.to_i, 'name' => name }.merge(Arroyo::Commercial::BoardRow.counts(by_seller[id] || [])) }
                .sort_by { |item| [-item['received'], item['name']] }
  end

  def days
    by_date = rows.group_by(&:date)
    (filters.since_date..filters.until_date).map do |date|
      items = by_date[date] || []
      by_seller = items.select(&:seller?).group_by(&:bucket)
      { date: date.iso8601, total: Arroyo::Commercial::BoardRow.counts(items),
        sellers: seller_names.keys.index_with { |id| Arroyo::Commercial::BoardRow.counts(by_seller[id] || []) } }
    end
  end

  def info_labels
    board['info_labels'].select { |item| item['enabled'] }.map do |item|
      { label: item['label'], count: rows.count { |row| row.labels.include?(item['label']) } }
    end
  end

  def repurchases
    { repeat_sales: rows.count { |row| repeat_sale?(row) }, post_sale_replies: rows.count { |row| row.event?('post_sale_reply') } }
  end

  def repeat_sale?(row)
    return false unless row.stage == 'won'

    at = row.record.outcome_at || row.record.started_at
    earlier_sales.fetch(row.record.contact_id, []).any? { |id, sold_at| id != row.record.id && sold_at && sold_at < at }
  end

  # Ventas anteriores por contacto: consultas ganadas y compras de postventa (que pueden no tener consulta).
  def earlier_sales
    @earlier_sales ||= begin
      contacts = rows.map { |row| row.record.contact_id }.uniq
      wins = Arroyo::Opportunity.where(account: @account, state: 'won', contact_id: contacts).pluck(:contact_id, :id, :outcome_at)
      purchases = Arroyo::PostSalePurchase.where(account: @account, contact_id: contacts).pluck(:contact_id, :opportunity_id, :purchased_at)
      (wins + purchases).group_by(&:first).transform_values { |items| items.map { |item| item.drop(1) } }
    end
  end

  def post_sale_issues
    scope = Arroyo::FollowUp.joins(:purchase).where(account: @account, status: POST_SALE_ISSUES)
                            .where('COALESCE(arroyo_follow_ups.attempted_at, arroyo_follow_ups.scheduled_at) BETWEEN ? AND ?',
                                   filters.time_range.begin, filters.time_range.end)
    scope = scope.where(arroyo_post_sale_purchases: { inbox_id: inbox_ids }) if inbox_ids
    { count: scope.count, items: scope.includes(purchase: [:seller, { conversation: :contact }])
                                      .order(scheduled_at: :desc).limit(ISSUES_LIMIT).map { |item| issue_json(item) } }
  end

  def issue_json(item)
    conversation = item.purchase.conversation
    { id: item.id, stage: item.stage, status: item.status, scheduled_at: item.scheduled_at&.iso8601,
      error: item.error_message.presence || item.error_code, product: item.purchase.product,
      seller: item.purchase.seller&.available_name, conversation_id: conversation&.display_id, contact: conversation&.contact&.name }
  end

  def matches?(row, filter)
    filter.all? do |name, value|
      matcher = MATCHERS[name.to_s]
      matcher.nil? || instance_exec(row, value.to_s, &matcher)
    end
  end

  # Un origen se puede pedir como nodo del gráfico (incluye "other"), como campaña o como anuncio.
  MATCHERS = {
    'origin' => ->(row, value) { [flow.origin_of(row), origins.key(row.record, level), origins.key(row.record, 'ad')].include?(value) },
    'bucket' => ->(row, value) { row.bucket == value },
    'stage' => ->(row, value) { row.stage == value },
    'attended' => ->(row, value) { row.attended?.to_s == value },
    'label' => ->(row, value) { row.labels.include?(value) },
    'date' => ->(row, value) { row.date.iso8601 == value },
    'metric' => ->(row, value) { metric?(row, value) }
  }.freeze

  def metric?(row, metric)
    case metric
    when 'repeat_sales' then repeat_sale?(row)
    when 'post_sale_replies' then row.event?('post_sale_reply')
    when 'nudged' then row.nudged?
    when 'organic' then organic?(row)
    else true
    end
  end
end
