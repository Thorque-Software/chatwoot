class Arroyo::SocialReply < ApplicationRecord
  STATUSES = %w[pending_configuration queued publishing published failed unconfirmed].freeze
  belongs_to :account
  belongs_to :comment, class_name: 'Arroyo::SocialComment', inverse_of: :replies
  belongs_to :message, optional: true
  belongs_to :sender, class_name: 'User', optional: true
  validates :status, inclusion: { in: STATUSES }
  validates :client_request_id, uniqueness: { scope: :comment_id }, allow_nil: true
  validates :message_id, uniqueness: true, allow_nil: true
  validates :remote_reply_id, presence: true, if: -> { status == 'published' }
  validate :matching_account

  def sync_message!
    return unless message

    attrs = message.content_attributes.merge('arroyo_kind' => 'social_comment_reply', 'arroyo_public_reply_status' => status,
                                             'arroyo_social_reply_id' => id, 'arroyo_social_comment_id' => comment_id)
    attrs.delete('external_error')
    attrs['arroyo_public_reply_error'] = error_message
    message.update!(status: 'sent', content_attributes: attrs)
  end

  private

  def matching_account
    errors.add(:account, :invalid) unless comment.account_id == account_id && (!message || message.account_id == account_id)
  end
end
