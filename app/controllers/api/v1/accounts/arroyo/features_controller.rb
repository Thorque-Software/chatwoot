# Flags de Arroyo que necesita el frontend de cualquier usuario de la cuenta (ej. mostrar "Panel" en el menú).
class Api::V1::Accounts::Arroyo::FeaturesController < Api::V1::Accounts::BaseController
  def show
    setting = ::Arroyo::Setting.for(Current.account)
    render json: { timezone: setting.config['timezone'], agent_panel: setting.section(:agent_panel),
                   follow_up: { enabled: setting.feature_enabled?(:follow_up) },
                   post_sale: { enabled: setting.feature_enabled?(:post_sale),
                                has_records: ::Arroyo::PostSalePurchase.exists?(account: Current.account) } }
  end
end
