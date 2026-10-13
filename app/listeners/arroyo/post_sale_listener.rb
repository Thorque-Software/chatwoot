class Arroyo::PostSaleListener < BaseListener
  def conversation_updated(event)
    change = event.data[:changed_attributes]&.dig('label_list')
    return unless change

    conversation = event.data[:conversation]
    purchase = Arroyo::PostSalePurchase.find_by(conversation: conversation)
    purchase.cancel_pending! if purchase&.excluded?
    return unless newly_sold?(conversation, change)

    Arroyo::PostSale::RegisterPurchaseService.new(conversation: conversation, timestamp: event.timestamp).perform
  end

  private

  def newly_sold?(conversation, change)
    setting = Arroyo::Setting.for(conversation.account)
    return false unless setting.feature_enabled?(:post_sale)

    sold_label = setting.section(:post_sale)['trigger_label']
    Array(change.first).exclude?(sold_label) && Array(change.last).include?(sold_label)
  end
end
