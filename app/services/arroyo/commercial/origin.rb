# Origen de una consulta: el anuncio de Meta (Click-to-WhatsApp) que la trajo, o demanda orgánica si no hay ninguno.
# Arroyo::Ads::ReferralRecorderService guarda el anuncio en la conversación con la hora (ad_referral_at); acá se
# copia a la oportunidad para que una recompra posterior en la misma conversación no herede un anuncio viejo.
class Arroyo::Commercial::Origin
  FIELDS = %w[ad_id ad_name ad_headline ad_source_url ad_adset_id ad_adset_name ad_campaign_id ad_campaign_name].freeze
  NAME_FIELDS = %w[ad_name ad_adset_id ad_adset_name ad_campaign_id ad_campaign_name].freeze
  # Meta manda el referral en el mismo mensaje que abre la consulta; el margen cubre relojes y reintentos.
  FRESH = 10.minutes

  def self.snapshot(attributes)
    attributes.to_h.slice(*FIELDS).compact_blank
  end

  def self.organic?(origin)
    origin.blank? || origin['ad_id'].blank?
  end

  def initialize(opportunity:, conversation:)
    @opportunity = opportunity
    @conversation = conversation
  end

  # Llamado por Arroyo::Commercial::Lifecycle con cada mensaje entrante.
  def capture
    return if opportunity.origin.present? || !fresh_referral?

    opportunity.update!(origin: self.class.snapshot(attributes))
  end

  private

  attr_reader :opportunity, :conversation

  def attributes
    conversation.additional_attributes || {}
  end

  def fresh_referral?
    return false if attributes['ad_id'].blank?

    at = Time.zone.parse(attributes['ad_referral_at'].to_s)
    at.present? && at >= opportunity.started_at - FRESH
  rescue ArgumentError
    false
  end
end
