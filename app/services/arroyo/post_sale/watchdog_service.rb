class Arroyo::PostSale::WatchdogService
  pattr_initialize [:follow_up!]

  def perform
    follow_up.purchase.with_lock do
      purchase = follow_up.purchase
      Arroyo::PostSale::DeliveryService.new(follow_up: follow_up).perform if follow_up.message_id
      next purchase.cancel_pending! if purchase.excluded?

      follow_up.with_lock { check_timeout } unless follow_up.delivered?
      alert_timeout
    end
  end

  private

  def alert_timeout
    Arroyo::PostSale::AlertService.new(follow_up: follow_up).perform if %w[failed unconfirmed not_executed].include?(follow_up.status)
  end

  def check_timeout
    return unless %w[awaiting_plan scheduled queued sent].include?(follow_up.status)
    return unless due_at + config['delivery_timeout_hours'].hours <= Time.current

    status = follow_up.attempted? ? 'unconfirmed' : 'not_executed'
    follow_up.update!(status: status, error_message: I18n.t("arroyo.post_sale.errors.#{status}", locale: follow_up.account.locale))
  end

  def due_at
    return follow_up.attempted_at if follow_up.attempted?
    return follow_up.scheduled_at if follow_up.scheduled_at

    zone = ActiveSupport::TimeZone[Arroyo::Setting.for(follow_up.account).config['timezone']]
    zone.parse(deadline_date(zone).iso8601).change(hour: config['send_hour_local'])
  end

  def deadline_date(zone)
    date = follow_up.purchase.purchased_at.in_time_zone(zone).to_date + config['stages'][follow_up.stage]['days']
    config['skip_sundays'] && date.sunday? ? date + 1 : date
  end

  def config
    @config ||= Arroyo::Setting.for(follow_up.account).section(:post_sale)
  end
end
