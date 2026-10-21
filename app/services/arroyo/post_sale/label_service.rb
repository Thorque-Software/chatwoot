class Arroyo::PostSale::LabelService
  def self.clear_resolved(conversation)
    conversation.reload.with_lock do
      purchases = Arroyo::PostSalePurchase.where(conversation: conversation)
      next if Arroyo::FollowUp.exists?(purchase: purchases, manual_status: 'pending')
      next unless conversation.label_list.include?('seguimiento-manual')

      conversation.update_labels(conversation.label_list - ['seguimiento-manual'])
    end
  end
end
