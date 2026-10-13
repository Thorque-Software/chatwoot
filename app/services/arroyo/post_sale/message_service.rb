class Arroyo::PostSale::MessageService
  pattr_initialize [:follow_up!, :revision!, :content!, :template_params, :execution_id]

  def perform
    follow_up.purchase.with_lock do
      follow_up.with_lock { prepare_message }
    end
    Arroyo::PostSale::DeliveryService.new(follow_up: follow_up).perform
    follow_up
  rescue ActiveRecord::RecordInvalid => e
    record_creation_failure(e)
  end

  private

  def prepare_message
    purchase = follow_up.purchase
    raise Arroyo::PostSale::Error, 'stale_revision' unless purchase.revision.to_s == revision.to_s
    return if follow_up.attempted? || %w[scheduled awaiting_plan].exclude?(follow_up.status)
    return purchase.cancel_pending! if purchase.excluded?

    validate_schedule
    if template_params.blank? && !follow_up.conversation.can_reply?
      record_closed_window
    else
      create_message(purchase)
    end
  end

  def record_closed_window
    follow_up.update!(attempted_at: Time.current, status: 'failed', error_code: '131047',
                      error_message: I18n.t('arroyo.post_sale.errors.closed_window', locale: follow_up.account.locale))
  end

  def validate_schedule
    raise Arroyo::PostSale::Error, 'invalid_plan' unless follow_up.scheduled_at && follow_up.purchase.planned_revision == follow_up.purchase.revision
    raise Arroyo::PostSale::Error, 'not_due' if follow_up.scheduled_at > Time.current
  end

  def create_message(purchase)
    conversation = purchase.conversation
    reopen_conversation(conversation, purchase)
    message = Messages::MessageBuilder.new(nil, conversation, message_params(purchase)).perform
    follow_up.update!(message: message, attempted_at: Time.current, status: 'queued', execution_id: execution_id,
                      channel_used: template_params.present? ? 'template' : 'free_text', template_name: template_params&.dig('name'))
  end

  def message_params(purchase)
    { content: content, message_type: 'outgoing', private: false, template_params: template_params,
      content_attributes: { arroyo_kind: 'post_sale', arroyo_purchase_reference: purchase.reference,
                            arroyo_stage: follow_up.stage, arroyo_follow_up_id: follow_up.id } }
  end

  def reopen_conversation(conversation, purchase)
    conversation.open! unless conversation.open?
    return if conversation.assignee_id.present? || !purchase.account.users.exists?(id: purchase.seller_id)

    conversation.update!(assignee: purchase.seller)
  end

  def record_creation_failure(error)
    follow_up.purchase.with_lock do
      follow_up.reload.with_lock do
        follow_up.update!(attempted_at: Time.current, status: 'failed', error_message: error.message) unless follow_up.attempted?
      end
    end
    Arroyo::PostSale::AlertService.new(follow_up: follow_up).perform
    follow_up
  end
end
