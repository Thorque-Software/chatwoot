class Arroyo::PostSalePurchasePolicy < ApplicationPolicy
  def update?
    @account_user.administrator? || record.seller_id == @user.id
  end
end
