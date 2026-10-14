class Arroyo::SocialComments::ImportService
  pattr_initialize [:channel!, :attributes!]

  def perform
    return if attributes['author_id'].present? && attributes['author_id'] == channel.external_account_id

    channel.with_lock do
      record = channel.comments.find_or_initialize_by(remote_id: attributes.fetch('remote_id'))
      timestamp = Time.iso8601(attributes.fetch('remote_updated_at'))
      next record if record.persisted? && record.remote_updated_at > timestamp

      update_record(record, timestamp)
      record
    end
  end

  private

  def update_record(record, timestamp)
    record.assign_attributes(attributes.slice('thread_id', 'parent_id', 'author_id', 'author_name', 'body', 'media_id', 'post_url', 'comment_url')
                                      .compact_blank.merge(account: channel.account, remote_updated_at: timestamp))
    record.thread_id ||= record.remote_id
    if attributes['deleted'] || record.deleted_at?
      record.deleted_at ||= timestamp
    elsif record.new_record?
      create_native_message(record)
    elsif record.message
      record.message.update!(content: record.body)
    end
    record.save!
  end

  def create_native_message(record)
    contact_inbox = contact_inbox_for(record)
    record.conversation = conversation_for(record, contact_inbox)
    record.message = record.conversation.messages.create!(
      account: channel.account, inbox: channel.inbox, sender: contact_inbox.contact, content: record.body,
      message_type: 'incoming', source_id: record.remote_id,
      content_attributes: { arroyo_kind: 'social_comment', arroyo_public_author: record.author_name, arroyo_social_remote_id: record.remote_id }
    )
  end

  def contact_inbox_for(record)
    ContactInboxWithContactBuilder.new(inbox: channel.inbox, source_id: record.author_id,
                                       contact_attributes: { name: record.author_name.presence || record.author_id }).perform
  end

  def conversation_for(record, contact_inbox)
    parent = channel.comments.find_by(remote_id: record.parent_id) if record.parent_id.present?
    record.thread_id = parent.thread_id if parent
    existing = channel.comments.where(thread_id: record.thread_id).where.not(conversation_id: nil).first
    existing&.conversation || ConversationBuilder.new(params: { status: 'open' }, contact_inbox: contact_inbox).perform
  end
end
