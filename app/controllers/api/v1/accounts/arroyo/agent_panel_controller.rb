class Api::V1::Accounts::Arroyo::AgentPanelController < Api::V1::Accounts::BaseController
  before_action :check_feature_enabled
  before_action -> { load_filters(:report) }, only: [:show, :export]
  before_action -> { load_filters(:conversations) }, only: [:conversations]
  before_action -> { load_filters(:windows) }, only: [:windows]

  def show
    render json: ::Arroyo::AgentPanel::ReportBuilder.new(filters: @filters).build
  end

  def conversations
    render json: ::Arroyo::AgentPanel::ConversationsFinder.new(filters: @filters).perform
  end

  def windows
    render json: ::Arroyo::AgentPanel::WindowsFinder.new(filters: @filters).perform
  end

  def export
    @report = ::Arroyo::AgentPanel::ReportBuilder.new(filters: @filters).build
    response.headers['Content-Type'] = 'text/csv'
    response.headers['Content-Disposition'] = "attachment; filename=panel_vendedores_#{@report[:since]}_#{@report[:until]}.csv"
    render layout: false, template: 'api/v1/accounts/arroyo/agent_panel/export', formats: [:csv]
  end

  private

  def check_feature_enabled
    return if ::Arroyo::Setting.for(Current.account).feature_enabled?(:agent_panel)

    render json: { error: I18n.t('arroyo.agent_panel.disabled') }, status: :forbidden
  end

  def load_filters(context)
    @filters = ::Arroyo::AgentPanel::Filters.new(account_user: Current.account_user, params: params)
    render json: { errors: @filters.errors.full_messages }, status: :unprocessable_entity unless @filters.valid?(context)
  end
end
