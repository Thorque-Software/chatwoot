class Arroyo::PostSale::CorrectDateService
  pattr_initialize [:purchase!, :purchased_at!, :user!]

  def perform
    date = Time.iso8601(purchased_at.to_s)
    raise Arroyo::PostSale::Error, 'invalid_date' if date > Time.current

    purchase.with_lock { apply_correction(date) }
    purchase
  rescue ArgumentError
    raise Arroyo::PostSale::Error, 'invalid_date'
  end

  private

  def apply_correction(date)
    raise Arroyo::PostSale::Error, 'cancelled' if purchase.cancelled_at

    purchase.update!(purchased_at: date, revision: purchase.revision + 1, date_changes: purchase.date_changes + [correction(date)])
    purchase.follow_ups.pending_dispatch.each { |follow_up| follow_up.update!(status: 'awaiting_plan', scheduled_at: nil) }
  end

  def correction(date)
    { from: purchase.purchased_at.iso8601, to: date.iso8601, user_id: user.id, corrected_at: Time.current.iso8601 }
  end
end
