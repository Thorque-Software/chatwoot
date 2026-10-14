class Arroyo::SocialComment < ApplicationRecord
  LINK_HOSTS = %w[instagram.com www.instagram.com facebook.com www.facebook.com m.facebook.com fb.com www.fb.com].freeze
  belongs_to :account
  belongs_to :channel, class_name: 'Arroyo::SocialChannel', inverse_of: :comments
  belongs_to :conversation, optional: true
  belongs_to :message, optional: true
  has_many :replies, class_name: 'Arroyo::SocialReply', foreign_key: :comment_id, inverse_of: :comment, dependent: :destroy
  validates :remote_id, :thread_id, :remote_updated_at, presence: true
  validates :remote_id, :thread_id, format: { with: Arroyo::SocialChannel::REMOTE_ID }
  validates :remote_id, uniqueness: { scope: :channel_id }
  validates :author_id, :body, :conversation, :message, presence: true, unless: :deleted_at?
  validate :validate_links
  validate :matching_account

  def self.safe_url?(value)
    uri = URI.parse(value)
    uri.scheme == 'https' && LINK_HOSTS.include?(uri.host&.downcase) && uri.userinfo.nil?
  rescue URI::InvalidURIError
    false
  end

  private

  def validate_links
    %i[post_url comment_url].each { |key| errors.add(key, :invalid) if self[key].present? && !self.class.safe_url?(self[key]) }
  end

  def matching_account
    errors.add(:account, :invalid) unless channel.account_id == account_id && (!conversation || conversation.account_id == account_id)
  end
end
