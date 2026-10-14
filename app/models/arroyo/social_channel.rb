class Arroyo::SocialChannel < ApplicationRecord
  PLATFORMS = %w[instagram facebook].freeze
  REMOTE_ID = /\A[A-Za-z0-9_.:-]+\z/

  belongs_to :account
  belongs_to :inbox
  has_many :comments, class_name: 'Arroyo::SocialComment', foreign_key: :channel_id, dependent: :destroy, inverse_of: :channel
  before_validation :normalize_configuration
  validates :platform, inclusion: { in: PLATFORMS }
  validates :inbox_id, uniqueness: true
  validates :external_account_id, format: { with: REMOTE_ID }, allow_nil: true
  validates :api_version, format: { with: /\Av\d{1,2}\.\d{1,2}\z/ }, allow_nil: true
  validates :external_account_id, :api_version, presence: true, if: :publishing_enabled?
  validate :account_matches_inbox

  def self.for_inbox(inbox)
    return unless inbox&.api?

    find_by(inbox_id: inbox.id, account_id: inbox.account_id)
  end

  def self.visible_to(account_user)
    scope = where(account_id: account_user.account_id)
    account_user.administrator? ? scope : scope.where(inbox_id: account_user.user.assigned_inboxes.select(:id))
  end

  def allowed_user?(user)
    membership = account.account_users.find_by(user: user)
    membership && (membership.administrator? || inbox.members.exists?(id: user.id))
  end

  def ready?
    publishing_enabled? && external_account_id.present? && api_version.present? && Arroyo::Setting.for(account).feature_enabled?(:social_comments)
  end

  private

  def normalize_configuration
    self.external_account_id = external_account_id.presence
    self.api_version = api_version.presence
  end

  def account_matches_inbox
    errors.add(:inbox, :invalid) unless inbox&.api? && inbox.account_id == account_id
  end
end
