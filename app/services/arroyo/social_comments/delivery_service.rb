class Arroyo::SocialComments::DeliveryService
  pattr_initialize [:account!]

  def claim
    return [] unless Arroyo::Setting.for(account).feature_enabled?(:social_comments)

    expire_claims
    Arroyo::SocialReply.transaction do
      replies.where(status: 'queued', comment_id: eligible_comments.select(:id))
             .order(:id).limit(20).lock('FOR UPDATE SKIP LOCKED').filter_map do |record|
        next unless record.sender && record.comment.channel.allowed_user?(record.sender) && record.message&.sender == record.sender

        claim_record(record)
      end
    end
  end

  def acknowledge(id, claim_token:, status:, remote_reply_id: nil, error_message: nil)
    record = replies.find(id)
    record.with_lock do
      raise Arroyo::SocialComments::Error.new('stale_claim', :conflict) unless claim_token.present? && record.claim_token == claim_token
      next record if record.status == 'published'

      validate_acknowledgment!(record, status, remote_reply_id)

      record.update!(status: status, remote_reply_id: remote_reply_id, published_at: status == 'published' ? Time.current : nil,
                     error_message: result_error(status, error_message))
      record.sync_message!
      record
    end
  end

  def retry!(record, user)
    record.with_lock do
      unless record.account_id == account.id && record.comment.channel.allowed_user?(user)
        raise Arroyo::SocialComments::Error.new('forbidden',
                                                :forbidden)
      end
      raise Arroyo::SocialComments::Error, 'unsafe_retry' unless %w[failed pending_configuration].include?(record.status)
      raise Arroyo::SocialComments::Error, 'not_configured' unless record.comment.channel.ready?
      raise Arroyo::SocialComments::Error, 'deleted' if record.comment.deleted_at?

      record.update!(status: 'queued', claim_token: nil, claimed_at: nil, error_message: nil)
      record.sync_message!
    end
    record
  end

  private

  def eligible_comments
    channels = Arroyo::SocialChannel.where(account: account, publishing_enabled: true).where.not(external_account_id: nil).where.not(api_version: nil)
    Arroyo::SocialComment.where(channel: channels, deleted_at: nil)
  end

  def claim_record(record)
    record.update!(status: 'publishing', claim_token: SecureRandom.uuid, claimed_at: Time.current, error_message: nil)
    record.sync_message!
    { id: record.id, claim_token: record.claim_token, platform: record.comment.channel.platform,
      api_version: record.comment.channel.api_version, remote_comment_id: record.comment.remote_id, content: record.message.content,
      external_account_id: record.comment.channel.external_account_id }
  end

  def validate_acknowledgment!(record, status, remote_reply_id)
    raise Arroyo::SocialComments::Error.new('stale_claim', :conflict) unless %w[publishing unconfirmed].include?(record.status)
    raise Arroyo::SocialComments::Error, 'invalid_status' unless %w[published failed unconfirmed].include?(status)
    raise Arroyo::SocialComments::Error, 'invalid_status' if status == 'published' && remote_reply_id.blank?
  end

  def result_error(status, error_message)
    return if status == 'published'

    error_message.presence || I18n.t("arroyo.social_comments.errors.#{status}")
  end

  def replies
    Arroyo::SocialReply.where(account: account)
  end

  def expire_claims
    replies.where(status: 'publishing').where(claimed_at: ...10.minutes.ago).find_each do |record|
      record.with_lock do
        next unless record.status == 'publishing' && record.claimed_at < 10.minutes.ago

        record.update!(status: 'unconfirmed', error_message: I18n.t('arroyo.social_comments.errors.unconfirmed'))
        record.sync_message!
      end
    end
  end
end
