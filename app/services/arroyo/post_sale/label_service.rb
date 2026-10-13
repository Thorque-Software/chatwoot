class Arroyo::PostSale::LabelService
  def self.clear_resolved(conversation)
    purchase = Arroyo::PostSalePurchase.find_by!(conversation: conversation)
    purchase.with_lock do
      conversation.with_lock do
        next if purchase.follow_ups.exists?(manual_status: 'pending')
        next unless conversation.label_list.include?('seguimiento-manual')

        conversation.update_labels(conversation.label_list - ['seguimiento-manual'])
      end
    end
  end
end
