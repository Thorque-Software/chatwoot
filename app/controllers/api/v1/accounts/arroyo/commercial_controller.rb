require 'csv'

class Api::V1::Accounts::Arroyo::CommercialController < Api::V1::Accounts::BaseController
  before_action :require_admin, only: %i[contexts assign follow_up_message complete_follow_up]
  before_action :require_funnel, except: :contexts
  before_action :load_query, only: %i[report opportunities export]
  rescue_from ::Arroyo::Commercial::Error, with: :render_error

  def report
    render json: builder.build
  end

  def opportunities
    records = builder.select(params[:metric].presence || 'received', scope: params[:scope].presence || 'cohort')
                     .sort_by { |item| [-item.started_at.to_f, -item.id] }
    render json: { opportunities: presenter(records.slice(offset, PAGE_SIZE) || []), meta: pagination(records.size) }
  end

  def create
    conversation = allowed_conversation
    record = ::Arroyo::Commercial::Lifecycle.new(conversation: conversation)
                                            .start!(request_key: params[:request_key].to_s, user: Current.user, product: params[:product])
    render json: { opportunity: presenter([record]).first }
  end

  def update
    record = access_query.base.find(params[:id])
    record = ::Arroyo::Commercial::Lifecycle.new(conversation: record.conversation)
                                            .outcome(record, outcome: params[:outcome], user: Current.user, product: params[:product])
    render json: { opportunity: presenter([record]).first }
  end

  def export
    detailed = params[:metric].present?
    rows = detailed ? opportunities_csv : summary_csv
    prefix = detailed ? 'arroyo_consultas' : 'arroyo_commercial'
    send_data rows, type: 'text/csv', filename: "#{prefix}_#{params[:since]}_#{params[:until]}.csv"
  end

  def assign
    raise ::Arroyo::Commercial::Error, 'disabled' unless panel_config['balanced_assignment_enabled']

    render json: ::Arroyo::Commercial::AssignmentService.new(conversation: allowed_conversation).perform
  end

  def contexts
    scope = context_scope
    records = scope.offset(offset).limit(PAGE_SIZE)
    render json: { contexts: records.map { |item| integration_context(item) }, meta: pagination(scope.count), config: panel_config }
  end

  def follow_up_message
    record = ::Arroyo::Commercial::FollowUpMessageService.new(conversation: allowed_conversation,
                                                              reference: params.require(:opportunity_reference), step: params.require(:step)).perform
    render json: record.slice(:id, :status, :source_id)
  end

  def complete_follow_up
    conversation = allowed_conversation
    record = ::Arroyo::Opportunity.find_by!(account: Current.account, conversation: conversation,
                                            reference: params.require(:opportunity_reference))
    render json: { completed: ::Arroyo::Commercial::FollowUpSchedule.new(opportunity: record).complete }
  end

  private

  PAGE_SIZE = 200

  def opportunities_csv
    records = builder.select(params[:metric], scope: params[:scope].presence || 'cohort')
    CSV.generate do |csv|
      csv << %w[reference conversation contact seller state].map { |field| I18n.t("arroyo.commercial.csv.#{field}") }
      records.each { |item| csv << opportunity_csv_row(item) }
    end
  end

  def opportunity_csv_row(item)
    [item.reference, item.conversation.display_id, item.contact.name, item.assignee&.available_name,
     I18n.t("arroyo.commercial.metrics.#{item.effective_state}")]
  end

  def summary_csv
    data = builder.build
    headers = ::Arroyo::Commercial::Report::METRICS.map { |metric| I18n.t("arroyo.commercial.metrics.#{metric}") }
    CSV.generate do |csv|
      csv << [I18n.t('arroyo.commercial.csv.seller'), *headers]
      csv << [I18n.t('arroyo.commercial.total'), *data[:totals].values]
      data[:agents].each { |agent| csv << [agent[:name], *agent[:totals].values] }
    end
  end

  def context_scope
    scope = ::Arroyo::Opportunity.where(account: Current.account)
    scope = scope.none unless panel_config['funnel_enabled']
    ids = scope.select('MAX(arroyo_opportunities.id)').group(:conversation_id)
    scope = scope.where(id: ids).order(:id).includes(:account, :conversation, :contact, events: :message)
    return scope if params[:conversation_id].blank?

    scope.joins(:conversation).where(conversations: { display_id: params[:conversation_id] })
  end

  def access_query
    ::Arroyo::Commercial::Query.new(account_user: Current.account_user, params: params)
  end

  def panel_config
    @panel_config ||= ::Arroyo::Setting.for(Current.account).section(:agent_panel)
  end

  def require_admin
    check_admin_authorization?
  end

  def require_funnel
    setting = ::Arroyo::Setting.for(Current.account)
    return if panel_config['funnel_enabled'] && setting.feature_enabled?(:agent_panel)

    raise ::Arroyo::Commercial::Error.new('disabled', status: :forbidden)
  end

  def load_query
    @query = access_query
    render json: { errors: @query.filters.errors.full_messages }, status: :unprocessable_entity unless @query.filters.valid?(:report)
  end

  def builder
    @builder ||= ::Arroyo::Commercial::Report.new(query: @query)
  end

  def allowed_conversation
    conversation = Current.account.conversations.find_by!(display_id: params.require(:conversation_id))
    raise ActiveRecord::RecordNotFound unless Current.account_user.administrator? || access_query.base.exists?(conversation_id: conversation.id) ||
                                              (conversation.assignee_id == Current.user.id && Current.user.inboxes.exists?(id: conversation.inbox_id))

    conversation
  end

  def presenter(records)
    ::Arroyo::Commercial::Presenter.new(records).as_json
  end

  def integration_context(item)
    state = item.effective_state
    schedule = ::Arroyo::Commercial::FollowUpSchedule.new(opportunity: item)
    { conversation_id: item.conversation.display_id, opportunity_reference: item.reference, state: state,
      last_client_at: item.last_client_at&.iso8601, last_human_at: item.last_human_at&.iso8601,
      commercial_allowed: schedule.allowed?, follow_up: schedule.as_json }
  end

  def page
    [params[:page].to_i, 1].max
  end

  def offset
    (page - 1) * PAGE_SIZE
  end

  def pagination(total)
    { total: total, next_page: offset + PAGE_SIZE < total ? page + 1 : nil }
  end

  def render_error(error)
    render json: { errors: [error.message], code: error.code }, status: error.status
  end
end
