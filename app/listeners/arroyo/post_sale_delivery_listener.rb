class Arroyo::PostSaleDeliveryListener < BaseListener
  def message_updated(event)
    message = event.data[:message]
    return unless message.content_attributes['arroyo_kind'] == 'post_sale'

    follow_up = Arroyo::FollowUp.find_by(message_id: message.id, account_id: message.account_id)
    Arroyo::PostSale::DeliveryService.new(follow_up: follow_up).perform if follow_up
  end
end
