# Guarda en la conversación el `referral` que Meta manda en el primer mensaje de un anuncio Click-to-WhatsApp.
# Meta informa solo el ID del anuncio (source_id), no el nombre de la campaña.
class Arroyo::Ads::ReferralRecorderService
  SOURCE = 'whatsapp_ad'.freeze
  FIELDS = {
    'ad_id' => :source_id,
    'ad_source_type' => :source_type,
    'ad_source_url' => :source_url,
    'ad_headline' => :headline,
    'ad_body' => :body,
    'ad_media_type' => :media_type,
    'ad_ctwa_clid' => :ctwa_clid
  }.freeze

  pattr_initialize [:conversation!, :message!]

  def perform
    return if referral.blank? || !enabled?

    conversation.update!(additional_attributes: conversation.additional_attributes.merge(attributes))
    resolve_campaign
  end

  private

  def referral
    message[:referral]
  end

  def enabled?
    ::Arroyo::Setting.for(conversation.account).feature_enabled?(:ads_attribution)
  end

  # La conversación todavía puede estar dentro de la transacción del webhook: se espera a que se confirme.
  def resolve_campaign
    return if attributes['ad_id'].blank? || ::Arroyo::Setting.for(conversation.account).meta_ads_token.blank?

    ::Arroyo::Ads::CampaignResolverJob.set(wait: 10.seconds).perform_later(conversation.id)
  end

  def attributes
    FIELDS.transform_values { |key| referral[key] }.compact.merge('ad_source' => SOURCE)
  end
end
