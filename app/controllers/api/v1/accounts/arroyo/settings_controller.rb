class Api::V1::Accounts::Arroyo::SettingsController < Api::V1::Accounts::BaseController
  STAGE_PARAMS = %i[days free_text template].freeze

  before_action :check_authorization
  before_action :set_setting

  def show; end

  def update
    @setting.merge_config(config_params)
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

  def config_params
    params.require(:config).permit(
      :timezone,
      window_keeper: [:enabled, :nudge_after_hours, :only_assigned, :nudge_text, :reengagement_template,
                      { only_statuses: [], nudge_buttons: [], skip_labels: [] }],
      post_sale: [:enabled, :trigger_label, :send_hour_local, :skip_sundays, :delivery_timeout_hours, :alert_email,
                  { alert_user_ids: [], stages: ::Arroyo::Setting::STAGES.index_with { STAGE_PARAMS } }],
      agent_panel: %i[enabled agents_see_only_own hide_native_reports],
      email_marketing: %i[enabled max_per_hour max_per_day footer_html]
    )
  end
end
