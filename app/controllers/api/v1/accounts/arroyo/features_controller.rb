# Flags de Arroyo que necesita el frontend de cualquier usuario de la cuenta (ej. mostrar "Panel" en el menú).
class Api::V1::Accounts::Arroyo::FeaturesController < Api::V1::Accounts::BaseController
  def show
    setting = ::Arroyo::Setting.for(Current.account)
    render json: { timezone: setting.config['timezone'], agent_panel: setting.section(:agent_panel),
                   social_comments: setting.section(:social_comments).merge(inboxes: social_inboxes),
                   post_sale: { enabled: setting.feature_enabled?(:post_sale),
                                has_records: ::Arroyo::PostSalePurchase.exists?(account: Current.account) } }
  end

  private

  def social_inboxes
    ::Arroyo::SocialChannel.visible_to(Current.account_user).map do |channel|
      { inbox_id: channel.inbox_id, platform: channel.platform, ready: channel.ready? }
    end
  end
end
