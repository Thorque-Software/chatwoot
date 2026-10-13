class Arroyo::PostSale::DeliveryService
  pattr_initialize [:follow_up!]

  def perform
    follow_up.purchase.with_lock do
      follow_up.with_lock do
        message = follow_up.message&.reload
        reconcile(message) if message
      end
    end
    Arroyo::PostSale::AlertService.new(follow_up: follow_up).perform if follow_up.status == 'failed'
    follow_up
  end

  private

  def reconcile(message)
    if message.delivered? || message.read?
      confirm_delivery(message)
    elsif message.failed? && !follow_up.delivered?
      record_failure(message)
    elsif accepted?(message)
      follow_up.update!(status: 'sent')
    end
  end

  def accepted?(message)
    message.source_id.present? && %w[queued sent].include?(follow_up.status)
  end

  def confirm_delivery(message)
    status = follow_up.status == 'read' ? 'read' : message.status
    attrs = { status: status, delivered_at: follow_up.delivered_at || message.updated_at }
    attrs[:read_at] = follow_up.read_at || message.updated_at if message.read?
    if follow_up.manual_status == 'pending'
      attrs[:manual_status] = 'closed_automatically'
      attrs[:resolved_at] = Time.current
    end
    follow_up.update!(attrs)
    Arroyo::PostSale::LabelService.clear_resolved(follow_up.conversation)
  end

  def record_failure(message)
    error = message.external_error.to_s
    match = error.match(/\A(\d+):\s*(.*)\z/m)
    text = error.presence || I18n.t('arroyo.post_sale.errors.send_failed', locale: follow_up.account.locale)
    follow_up.update!(status: 'failed', error_code: match&.[](1), error_message: text)
  end
end
