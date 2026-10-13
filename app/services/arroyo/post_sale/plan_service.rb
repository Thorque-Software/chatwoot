class Arroyo::PostSale::PlanService
  pattr_initialize [:purchase!, :revision!, :stages!]

  def perform
    purchase.with_lock do
      validate_purchase
      next if purchase.planned_revision == purchase.revision

      dates = parse_dates
      purchase.follow_ups.pending_dispatch.each { |follow_up| apply_date(follow_up, dates.fetch(follow_up.stage)) }
      purchase.update!(planned_revision: purchase.revision)
    end
    alert_missed_stages
    purchase
  end

  private

  def alert_missed_stages
    purchase.follow_ups.where(status: 'not_executed').find_each { |follow_up| Arroyo::PostSale::AlertService.new(follow_up: follow_up).perform }
  end

  def validate_purchase
    raise Arroyo::PostSale::Error, 'stale_revision' unless revision.to_s == purchase.revision.to_s
    raise Arroyo::PostSale::Error, 'cancelled' if purchase.excluded?
  end

  def apply_date(follow_up, date)
    correction = purchase.date_changes.last&.stringify_keys
    if correction && date < Time.iso8601(correction['corrected_at'])
      follow_up.update!(scheduled_at: date, status: 'not_executed',
                        error_message: I18n.t('arroyo.post_sale.errors.corrected_past', locale: purchase.account.locale))
    else
      follow_up.update!(scheduled_at: date, status: 'scheduled')
    end
  end

  def parse_dates
    input = stages.to_h.stringify_keys
    raise Arroyo::PostSale::Error, 'invalid_plan' unless input.keys.sort == Arroyo::FollowUp::STAGES.sort

    input.transform_values { |value| Time.iso8601(value.to_s) }
  rescue ArgumentError
    raise Arroyo::PostSale::Error, 'invalid_plan'
  end
end
