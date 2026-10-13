class Arroyo::PostSale::RegisterPurchaseService
  pattr_initialize [:conversation!, :timestamp!]

  def perform
    return unless eligible?

    conversation.with_lock do
      purchase = Arroyo::PostSalePurchase.find_by(conversation: conversation)
      purchase || create_purchase
    end
  end

  private

  def eligible?
    conversation.inbox.channel_type == 'Channel::Whatsapp' && conversation.inbox.channel.provider == 'whatsapp_cloud' &&
      !conversation.contact.blocked? && (conversation.label_list + conversation.contact.label_list).exclude?('no-contactar')
  end

  def create_purchase
    purchase = Arroyo::PostSalePurchase.create!(
      account: conversation.account, conversation: conversation, contact: conversation.contact,
      inbox: conversation.inbox, seller: conversation.assignee, purchased_at: timestamp, recorded_at: timestamp,
      product: product, rubro: rubro
    )
    Arroyo::FollowUp::STAGES.each { |stage| purchase.follow_ups.create!(account: purchase.account, stage: stage) }
    purchase
  end

  def product
    value = conversation.custom_attributes['producto_comprado'].presence || conversation.contact.custom_attributes['producto_comprado'].presence
    value || I18n.t("arroyo.post_sale.products.#{rubro.presence || 'generic'}", locale: conversation.account.locale)
  end

  def rubro
    return 'gym' if conversation.label_list.include?('aparatosgim')
    return 'bike' if conversation.label_list.include?('bici')

    'generic'
  end
end
