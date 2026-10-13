class Api::V1::Accounts::Arroyo::PostSaleController < Api::V1::Accounts::BaseController
  before_action :require_administrator, only: [:purchases, :plan, :create_message, :merge_attributes]
  before_action :require_enabled, only: [:plan, :create_message]
  before_action :require_panel, only: [:index, :correct_date, :resolve]
  rescue_from ::Arroyo::PostSale::Error, with: :render_post_sale_error

  def purchases
    scope = ::Arroyo::PostSalePurchase.active.where(account: Current.account).order(:id)
    scope = scope.none unless setting.feature_enabled?(:post_sale)
    records = scope.offset(offset).limit(PAGE_SIZE).includes(:seller, :contact, :inbox, :conversation, :follow_ups)
    render json: { purchases: records.map { |record| presenter.purchase(record) }, config: integration_config,
                   meta: pagination(scope.count) }
  end

  def plan
    record = purchase_record
    ::Arroyo::PostSale::PlanService.new(purchase: record, revision: params.require(:revision),
                                        stages: params.require(:stages).permit(*::Arroyo::FollowUp::STAGES)).perform
    render json: { purchase: presenter.purchase(record.reload) }
  end

  def index
    scope = ::Arroyo::PostSale::Query.new(account_user: Current.account_user, params: params).perform
    totals = scope.group(:status).count.merge('manual_pending' => scope.where(manual_status: 'pending').count)
    records = scope.order(created_at: :desc, id: :asc).offset(offset).limit(PAGE_SIZE)
                   .includes(:message, purchase: [:seller, :contact, :inbox, :conversation, :follow_ups])
    render json: { follow_ups: records.map { |record| presenter.follow_up(record) }, totals: totals,
                   timezone: setting.config['timezone'], meta: pagination(scope.count) }
  end

  def create_message
    record = follow_up_record
    template = params.permit(template_params: {})[:template_params]&.to_h
    ::Arroyo::PostSale::MessageService.new(follow_up: record, revision: params.require(:revision), content: params.require(:content),
                                           execution_id: params[:execution_id], template_params: template).perform
    render json: presenter.follow_up(record.reload)
  end

  def correct_date
    record = purchase_record
    authorize(record, :update?)
    ::Arroyo::PostSale::CorrectDateService.new(purchase: record, purchased_at: params.require(:purchased_at), user: Current.user).perform
    render json: { purchase: presenter.purchase(record.reload) }
  end

  def resolve
    record = follow_up_record
    authorize(record, :resolve?)
    ::Arroyo::PostSale::ResolveService.new(follow_up: record, user: Current.user,
                                           method: params.require(:method), note: params.require(:note)).perform
    render json: { follow_up: presenter.follow_up(record.reload) }
  end

  def merge_attributes
    conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    attributes = params.require(:custom_attributes).permit(*::Arroyo::PostSale::AttributesService::KEYS)
    ::Arroyo::PostSale::AttributesService.new(conversation: conversation, attributes: attributes).perform
    render json: { custom_attributes: conversation.custom_attributes }
  end

  private

  PAGE_SIZE = 200

  def setting
    @setting ||= ::Arroyo::Setting.for(Current.account)
  end

  def presenter
    @presenter ||= ::Arroyo::PostSale::Presenter.new(account_user: Current.account_user)
  end

  def purchase_record
    ::Arroyo::PostSalePurchase.find_by!(account: Current.account, reference: params[:reference])
  end

  def follow_up_record
    ::Arroyo::FollowUp.find_by!(account: Current.account, id: params[:id])
  end

  def require_administrator
    check_admin_authorization?
  end

  def require_enabled
    raise ::Arroyo::PostSale::Error, 'disabled' unless setting.feature_enabled?(:post_sale)
  end

  def require_panel
    raise ::Arroyo::PostSale::Error, 'panel_disabled' unless setting.feature_enabled?(:agent_panel)
  end

  def integration_config
    setting.section(:post_sale).merge('timezone' => setting.config['timezone'], 'template_language' => 'es_AR', 'template_category' => 'MARKETING')
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

  def render_post_sale_error(error)
    render json: { errors: [error.message] }, status: error.status
  end
end
