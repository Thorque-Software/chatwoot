# Parámetros del panel de vendedores: rango de fechas locales, vendedores, inboxes y agrupación.
# Aplica también los permisos: un agente con agents_see_only_own solo ve lo suyo.
class Arroyo::AgentPanel::Filters
  include ActiveModel::Validations

  GROUP_BY = %w[day week].freeze
  METRICS = %w[conversations_attended messages_sent assignments first_response_median windows_closed sales].freeze
  MAX_RANGE_DAYS = 366
  DATE_FORMAT = /\A\d{4}-\d{2}-\d{2}\z/
  ID_FORMAT = /\A\d+\z/

  attr_reader :account, :account_user, :params, :setting

  validate :validate_dates, on: [:report, :conversations]
  validate :validate_group_by, on: [:report, :conversations]
  validate :validate_metric, on: :conversations
  validate :validate_ids

  def initialize(account_user:, params:)
    @account_user = account_user
    @account = account_user.account
    @params = params
    @setting = Arroyo::Setting.for(account)
  end

  def timezone
    ActiveSupport::TimeZone[setting.config['timezone']]
  end

  def since_date
    Date.iso8601(params[:since])
  end

  def until_date
    Date.iso8601(params[:until])
  end

  def time_range
    timezone.parse(params[:since]).beginning_of_day..timezone.parse(params[:until]).end_of_day
  end

  def group_by
    params[:group_by].presence || 'day'
  end

  def metric
    params[:metric]
  end

  def periods
    return (since_date..until_date).to_a if group_by == 'day'

    (since_date.beginning_of_week(:monday)..until_date).step(7).to_a
  end

  # Expresión SQL que convierte una columna UTC en el día/semana local del negocio
  def period_sql(column)
    tz = ActiveRecord::Base.connection.quote(timezone.tzinfo.name)
    "date_trunc('#{group_by}', (#{column} AT TIME ZONE 'UTC') AT TIME ZONE #{tz})::date"
  end

  def only_own?
    !account_user.administrator? && setting.section(:agent_panel)['agents_see_only_own']
  end

  def user_ids
    return [account_user.user_id] if only_own?
    return requested_user_ids if params[:user_ids].present?

    account.account_users.pluck(:user_id)
  end

  # nil = sin restricción por asignado (admin sin filtro de vendedores: incluye conversaciones sin asignar)
  def assignee_ids
    user_ids if only_own? || params[:user_ids].present?
  end

  def users
    account.users.where(id: user_ids).order(:name)
  end

  def inbox_ids
    params[:inbox_ids].map(&:to_i) if params[:inbox_ids].present?
  end

  def sale_label
    setting.section(:post_sale)['trigger_label']
  end

  # Los errores de validación se reportan sobre los params crudos
  def read_attribute_for_validation(key)
    params[key]
  end

  private

  def requested_user_ids
    params[:user_ids].map(&:to_i)
  end

  def validate_dates
    return errors.add(:since, :invalid) unless params[:since].to_s.match?(DATE_FORMAT) && valid_date?(params[:since])
    return errors.add(:until, :invalid) unless params[:until].to_s.match?(DATE_FORMAT) && valid_date?(params[:until])

    errors.add(:until, :invalid) unless (0...MAX_RANGE_DAYS).cover?((until_date - since_date).to_i)
  end

  def validate_group_by
    errors.add(:group_by, :inclusion) unless GROUP_BY.include?(group_by)
  end

  def validate_metric
    errors.add(:metric, :inclusion) unless METRICS.include?(metric)
  end

  def validate_ids
    errors.add(:user_ids, :invalid) unless valid_ids?(params[:user_ids], account.account_users.pluck(:user_id))
    errors.add(:inbox_ids, :invalid) unless valid_ids?(params[:inbox_ids], account.inboxes.pluck(:id))
  end

  def valid_ids?(ids, allowed_ids)
    return true if ids.nil?

    ids.is_a?(Array) && ids.all? { |id| id.to_s.match?(ID_FORMAT) } && (ids.map(&:to_i) - allowed_ids).empty?
  end

  def valid_date?(value)
    Date.iso8601(value)
  rescue Date::Error
    false
  end
end
