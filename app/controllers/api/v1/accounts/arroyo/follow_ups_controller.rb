class Api::V1::Accounts::Arroyo::FollowUpsController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?
  before_action :require_funnel
  rescue_from ::Arroyo::Commercial::Error, with: :render_error

  def index
    render json: list.as_json
  end

  def send_now
    schedule = ::Arroyo::Commercial::FollowUpSchedule.new(opportunity: opportunity)
    ::Arroyo::Commercial::FollowUpMessageService.new(conversation: conversation, reference: opportunity.reference,
                                                     step: schedule.sent_count + 1, immediate: true).perform
    render json: { follow_up: list.row_for(conversation.reload) }
  end

  def reschedule
    ::Arroyo::Commercial::FollowUpSchedule.new(opportunity: opportunity).reschedule(date: parsed_date, actor: Current.user)
    render json: { follow_up: list.row_for(conversation.reload) }
  end

  def enroll
    ids = params.permit(conversation_ids: []).require(:conversation_ids)
    found = Current.account.conversations.where(display_id: ids).to_a
    results = found.to_h { |item| [item.display_id, enroll_conversation(item)] }
    missing = ids.map(&:to_i) - results.keys
    render json: { enrolled: results.select { |_id, enrolled| enrolled }.keys,
                   skipped: results.reject { |_id, enrolled| enrolled }.keys.map { |id| { conversation_id: id, reason: 'not_eligible' } } +
                            missing.map { |id| { conversation_id: id, reason: 'not_found' } } }
  end

  private

  def require_funnel
    setting = ::Arroyo::Setting.for(Current.account)
    return if setting.section(:agent_panel)['funnel_enabled'] && setting.feature_enabled?(:agent_panel)

    raise ::Arroyo::Commercial::Error.new('disabled', status: :forbidden)
  end

  def list
    @list ||= ::Arroyo::Commercial::FollowUpList.new(account: Current.account)
  end

  def conversation
    @conversation ||= Current.account.conversations.find_by!(display_id: params.require(:conversation_id))
  end

  def opportunity
    @opportunity ||= ::Arroyo::Opportunity.find_by!(account: Current.account, conversation: conversation,
                                                    reference: params.require(:opportunity_reference))
  end

  def parsed_date
    Date.iso8601(params.require(:date))
  rescue Date::Error
    raise ::Arroyo::Commercial::Error, 'invalid_date'
  end

  def enroll_conversation(conversation)
    return false unless conversation.label_list.include?('seguimiento')

    lifecycle = ::Arroyo::Commercial::Lifecycle.new(conversation: conversation)
    lifecycle.labels(actor: Current.user, at: Time.current, change: [[], ['seguimiento']])
    current = lifecycle.current
    current.present? && ::Arroyo::Commercial::FollowUpSchedule.new(opportunity: current).active?
  end

  def render_error(error)
    render json: { errors: [error.message], code: error.code }, status: error.status
  end
end
