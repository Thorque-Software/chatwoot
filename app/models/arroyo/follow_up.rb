class Arroyo::FollowUp < ApplicationRecord
  STAGES = %w[d1 d7 d30].freeze
  STATUSES = %w[awaiting_plan scheduled queued sent delivered read failed unconfirmed not_executed cancelled].freeze
  RESOLUTION_METHODS = %w[call personal_whatsapp other].freeze

  belongs_to :account
  belongs_to :purchase, class_name: 'Arroyo::PostSalePurchase', inverse_of: :follow_ups
  belongs_to :message, optional: true
  belongs_to :alert_message, class_name: 'Message', optional: true
  belongs_to :alert_assignee, class_name: 'User', optional: true
  belongs_to :resolved_by, class_name: 'User', optional: true

  validates :stage, inclusion: { in: STAGES }, uniqueness: { scope: :purchase_id }
  validates :status, inclusion: { in: STATUSES }
  validates :message_id, uniqueness: true, allow_nil: true
  validates :manual_status, inclusion: { in: %w[pending resolved closed_automatically] }, allow_nil: true
  validates :resolution_method, inclusion: { in: RESOLUTION_METHODS }, allow_nil: true

  scope :pending_dispatch, -> { where(status: %w[awaiting_plan scheduled]) }

  def attempted?
    attempted_at.present? || message_id.present?
  end

  def delivered?
    %w[delivered read].include?(status)
  end

  def conversation
    purchase.conversation
  end
end
