class AddMetaAdsTokenToArroyoSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :arroyo_settings, :meta_ads_token, :text
  end
end
