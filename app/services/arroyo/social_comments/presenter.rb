class Arroyo::SocialComments::Presenter
  def channel(record)
    { id: record.id, inbox_id: record.inbox_id, name: record.inbox.name, platform: record.platform,
      external_account_id: record.external_account_id, api_version: record.api_version,
      publishing_enabled: record.publishing_enabled, ready: record.ready? }
  end

  def comment(record)
    { id: record.id, platform: record.channel.platform, inbox_id: record.channel.inbox_id, author_name: record.author_name,
      body: record.body, media_id: record.media_id, remote_id: record.remote_id, thread_id: record.thread_id,
      post_url: record.post_url, comment_url: record.comment_url, deleted: record.deleted_at.present?,
      conversation_id: record.conversation&.display_id, message_id: record.message_id, created_at: record.created_at,
      replies: record.replies.order(:created_at).map { |item| reply(item) } }
  end

  def reply(record)
    { id: record.id, message_id: record.message_id, sender_name: record.sender&.name, content: record.message&.content,
      status: record.status, error_message: record.error_message, remote_reply_id: record.remote_reply_id,
      created_at: record.created_at, published_at: record.published_at,
      can_retry: %w[failed pending_configuration].include?(record.status) && record.comment.channel.ready? && !record.comment.deleted_at? }
  end
end
