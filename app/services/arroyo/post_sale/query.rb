class Arroyo::PostSale::Query
  pattr_initialize [:account_user!, :params!]

  def perform
    scope = Arroyo::FollowUp.joins(:purchase).where(account: account_user.account)
    scope = own_follow_ups(scope) unless account_user.administrator?
    scope = apply_filters(scope)
    apply_dates(scope)
  end

  private

  def own_follow_ups(scope)
    scope.where('arroyo_post_sale_purchases.seller_id = :user OR arroyo_follow_ups.alert_assignee_id = :user', user: account_user.user_id)
  end

  def apply_filters(scope)
    %i[manual_status status stage].each do |filter|
      scope = scope.where(filter => params[filter]) if params[filter].present?
    end
    { purchase_reference: :reference, inbox_ids: :inbox_id, user_ids: :seller_id }.each do |param, column|
      scope = scope.where(arroyo_post_sale_purchases: { column => params[param] }) if params[param].present?
    end
    scope
  end

  def apply_dates(scope)
    return scope if params[:since].blank? && params[:until].blank?

    first = Date.iso8601(params[:since].to_s)
    last = Date.iso8601(params[:until].to_s)
    raise Arroyo::PostSale::Error, 'invalid_date' unless (0..366).cover?((last - first).to_i)

    scope.where(arroyo_post_sale_purchases: { purchased_at: date_range(first, last) })
  rescue ArgumentError
    raise Arroyo::PostSale::Error, 'invalid_date'
  end

  def date_range(first, last)
    timezone = Arroyo::Setting.for(account_user.account).config['timezone']
    zone = ActiveSupport::TimeZone[timezone]
    zone.parse(first.iso8601).beginning_of_day..zone.parse(last.iso8601).end_of_day
  end
end
