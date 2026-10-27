class Arroyo::Ads::CampaignResolverJob < ApplicationJob
  queue_as :low

  retry_on Arroyo::Ads::LookupError, wait: 5.minutes, attempts: 3 do |job, error|
    Rails.logger.error "Arroyo ads: no se pudo resolver la campaña de la conversación #{job.arguments.first}: #{error.message}"
  end

  def perform(conversation_id)
    conversation = Conversation.find(conversation_id)
    ad_id = conversation.additional_attributes['ad_id']
    token = Arroyo::Setting.for(conversation.account).meta_ads_token
    return if ad_id.blank? || token.blank?

    names = Rails.cache.fetch("arroyo/ads/#{ad_id}", expires_in: 1.day) do
      Arroyo::Ads::CampaignLookupService.new(token: token, ad_id: ad_id).perform
    end
    conversation.update!(additional_attributes: conversation.additional_attributes.merge(names))
  end
end
