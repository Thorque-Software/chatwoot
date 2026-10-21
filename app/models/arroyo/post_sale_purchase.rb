class Arroyo::PostSalePurchase < ApplicationRecord
  belongs_to :account
  belongs_to :conversation
  belongs_to :contact
  belongs_to :inbox
  belongs_to :seller, class_name: 'User', optional: true
  belongs_to :opportunity, class_name: 'Arroyo::Opportunity', optional: true, inverse_of: :purchase
  has_many :follow_ups, class_name: 'Arroyo::FollowUp', foreign_key: :purchase_id, dependent: :destroy, inverse_of: :purchase

  before_validation :assign_reference, on: :create
  validates :reference, presence: true, uniqueness: true
  validates :conversation_id, uniqueness: true, if: -> { opportunity_id.nil? }
  validates :opportunity_id, uniqueness: true, allow_nil: true
  validates :purchased_at, :recorded_at, presence: true

  scope :active, -> { where(cancelled_at: nil) }

  def excluded?
    labels = conversation.label_list + contact.label_list
    cancelled_at.present? || contact.blocked? || labels.include?('no-contactar') || labels.include?('venta-cancelada') ||
      conversation.label_list.exclude?(Arroyo::Setting.for(account).section(:post_sale)['trigger_label'])
  end

  def cancel_pending!
    with_lock do
      update!(cancelled_at: Time.current) unless cancelled_at
      follow_ups.where(status: %w[awaiting_plan scheduled]).find_each { |follow_up| follow_up.update!(status: 'cancelled') }
      follow_ups.where(manual_status: 'pending').find_each do |follow_up|
        follow_up.update!(manual_status: 'closed_automatically', resolved_at: Time.current)
      end
      Arroyo::PostSale::LabelService.clear_resolved(conversation)
    end
  end

  private

  def assign_reference
    self.reference ||= SecureRandom.uuid
  end
end
