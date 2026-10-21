class Arroyo::Commercial::BackfillService
  pattr_initialize [:account!]

  def perform
    account.conversations.includes(:contact, :inbox, :assignee).find_each do |conversation|
      conversation.with_lock { backfill_conversation(conversation) }
    end
  end

  private

  def backfill_conversation(conversation)
    return if Arroyo::Opportunity.exists?(account: account, conversation: conversation)

    first_incoming = conversation.messages.where(message_type: :incoming, private: false).minimum(:created_at)
    purchase = Arroyo::PostSalePurchase.where(account: account, conversation: conversation).order(:purchased_at).first
    return unless first_incoming || purchase

    record = create_opportunity(conversation, first_incoming, purchase)
    record.events.create!(kind: 'received', source_key: 'backfill_received', origin: 'backfill', occurred_at: record.started_at)
    link_purchase(record, purchase) if purchase
  end

  def create_opportunity(conversation, first_incoming, purchase)
    Arroyo::Opportunity.create!(account: account, conversation: conversation, contact: conversation.contact, inbox: conversation.inbox,
                                assignee: purchase&.seller || conversation.assignee, result_user: purchase&.seller,
                                reference: SecureRandom.uuid, request_key: "backfill:#{conversation.id}", coverage: 'partial',
                                state: purchase ? 'won' : 'unknown', started_at: first_incoming || purchase.recorded_at,
                                outcome_at: purchase&.purchased_at, product: purchase&.product)
  end

  def link_purchase(record, purchase)
    purchase.update!(opportunity: record)
    record.events.create!(kind: 'won', source_key: 'backfill_won', origin: 'backfill', actor: purchase.seller, occurred_at: purchase.purchased_at)
  end
end
