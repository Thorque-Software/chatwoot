class Arroyo::FollowUpPolicy < ApplicationPolicy
  def resolve?
    @account_user.administrator? || record.purchase.seller_id == @user.id || record.alert_assignee_id == @user.id
  end
end
