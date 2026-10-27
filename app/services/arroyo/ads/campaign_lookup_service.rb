# Consulta a la Marketing API de Meta el anuncio, el conjunto y la campaña de un ad_id (el token necesita ads_read).
class Arroyo::Ads::CampaignLookupService
  BASE_URI = 'https://graph.facebook.com'.freeze
  FIELDS = 'name,adset{id,name},campaign{id,name}'.freeze

  pattr_initialize [:token!, :ad_id!]

  def perform
    response = HTTParty.get("#{BASE_URI}/#{api_version}/#{ad_id}", query: { fields: FIELDS }, headers: { 'Authorization' => "Bearer #{token}" })
    raise Arroyo::Ads::LookupError, response.dig('error', 'message') || response.code.to_s unless response.success?

    {
      'ad_name' => response['name'],
      'ad_adset_id' => response.dig('adset', 'id'), 'ad_adset_name' => response.dig('adset', 'name'),
      'ad_campaign_id' => response.dig('campaign', 'id'), 'ad_campaign_name' => response.dig('campaign', 'name')
    }.compact
  end

  private

  def api_version
    GlobalConfigService.load('WHATSAPP_API_VERSION', 'v22.0')
  end
end
