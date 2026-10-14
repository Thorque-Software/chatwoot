class Arroyo::SocialComments::ReplyService
  pattr_initialize [:channel!, :message!, :user, :request_id]

  def self.persist(message, user, request_id)
    channel = Arroyo::SocialChannel.for_inbox(message.inbox)
    return new(channel: channel, message: message, user: user, request_id: request_id).perform if channel && message.outgoing? && !message.private?

    message.save!
    message
  end

  def perform
    validate_human!
    comment = target_comment
    comment.with_lock do
      raise Arroyo::SocialComments::Error, 'deleted' if comment.deleted_at?

      existing = comment.replies.find_by(client_request_id: request_id) if request_id.present?
      next existing.message if existing

      persist_reply(comment)
    end
  end

  private

  def validate_human!
    raise Arroyo::SocialComments::Error.new('disabled', :forbidden) unless Arroyo::Setting.for(channel.account).feature_enabled?(:social_comments)

    raise Arroyo::SocialComments::Error.new('humans_only', :forbidden) unless human_sender?

    validate_content!
  end

  def human_sender?
    interactive_user? && channel.allowed_user?(user) && message.content_attributes['automation_rule_id'].blank?
  end

  def interactive_user?
    user.is_a?(User) && message.sender == user && Arroyo::SocialComments::HumanReplyContext.user == user
  end

  def validate_content!
    raise Arroyo::SocialComments::Error, 'text_only' if message.attachments.any? || message.content.blank? ||
                                                        (message.content_type.present? && !message.text?)
  end

  def target_comment
    scope = channel.comments.where(conversation_id: message.conversation_id)
    reply_to = message.content_attributes['in_reply_to']
    reply_to.present? ? scope.find_by!(message_id: reply_to) : scope.order(:id).find_by!(thread_id: scope.order(:id).first&.thread_id)
  end

  def persist_reply(comment)
    status = channel.ready? ? 'queued' : 'pending_configuration'
    message.content_attributes = message.content_attributes.merge('arroyo_kind' => 'social_comment_reply', 'arroyo_public_reply_status' => status)
    message.save!
    record = comment.replies.create!(account: channel.account, message: message, sender: user, client_request_id: request_id.presence,
                                     status: status, error_message: configuration_error(status))
    record.sync_message!
    message
  end

  def configuration_error(status)
    I18n.t('arroyo.social_comments.errors.not_configured') if status == 'pending_configuration'
  end
end
