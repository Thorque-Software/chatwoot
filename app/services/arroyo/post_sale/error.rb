class Arroyo::PostSale::Error < StandardError
  STATUSES = { 'disabled' => :forbidden, 'panel_disabled' => :forbidden, 'stale_revision' => :conflict,
               'not_due' => :conflict, 'no_pending_alert' => :conflict }.freeze
  attr_reader :status

  def initialize(key)
    @status = STATUSES.fetch(key, :unprocessable_entity)
    super(I18n.t("arroyo.post_sale.errors.#{key}"))
  end
end
