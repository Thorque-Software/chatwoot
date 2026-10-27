class Api::V1::Accounts::Arroyo::SettingsController < Api::V1::Accounts::BaseController
  STAGE_PARAMS = %i[days].freeze

  before_action :check_authorization
  before_action :set_setting

  def show; end

  def update
    @setting.merge_config(config_params)
    @setting.meta_ads_token = meta_ads_token if meta_ads_token.present?
    if @setting.save
      render :show
    else
      render json: { errors: @setting.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def check_authorization
    authorize(::Arroyo::Setting)
  end

  def set_setting
    @setting = ::Arroyo::Setting.for(Current.account)
  end

  def meta_ads_token
    params.dig(:config, :ads_attribution, :meta_ads_token)
  end

  def config_params
    params.require(:config).permit(
      :timezone,
      post_sale: [:enabled, :trigger_label, :send_hour_local, :skip_sundays, :delivery_timeout_hours, :alert_email,
                  { alert_user_ids: [], stages: ::Arroyo::Setting::STAGES.index_with { STAGE_PARAMS } }],
      agent_panel: [:enabled, :agents_see_only_own, :hide_native_reports, :funnel_enabled, :balanced_assignment_enabled,
                    :response_hours, :lookback_days, { seller_ids: [] }],
      follow_up: [:enabled, { aliases: %i[name alias] }],
      email_marketing: %i[enabled max_per_hour max_per_day footer_html],
      ads_attribution: %i[enabled]
    )
  end
end
