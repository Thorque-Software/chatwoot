# Serializa conversaciones para las listas del panel (drill-down y ventanas), con su último mensaje.
class Arroyo::AgentPanel::ConversationList
  CONTENT_PREVIEW_LENGTH = 160

  pattr_initialize :conversations

  def as_json(*)
    last_messages = last_messages_by_conversation
    conversations.map { |conversation| serialize(conversation, last_messages[conversation.id]) }
  end

  private

  def serialize(conversation, last_message)
    {
      id: conversation.id,
      display_id: conversation.display_id,
      status: conversation.status,
      contact: { id: conversation.contact_id, name: conversation.contact.name, phone_number: conversation.contact.phone_number },
      inbox: { id: conversation.inbox_id, name: conversation.inbox.name },
      assignee: conversation.assignee && { id: conversation.assignee_id, name: conversation.assignee.available_name },
      last_message: last_message,
      last_activity_at: conversation.last_activity_at.to_i
    }
  end

  def last_messages_by_conversation
    Message.unscoped
           .where(conversation_id: conversations.map(&:id), message_type: %i[incoming outgoing], private: false)
           .order(:conversation_id, created_at: :desc)
           .pluck(Arel.sql('DISTINCT ON (messages.conversation_id) messages.conversation_id'), :content, :message_type, :created_at)
           .to_h do |conversation_id, content, message_type, created_at|
             [conversation_id, { content: content&.truncate(CONTENT_PREVIEW_LENGTH), message_type: message_type, created_at: created_at.to_i }]
           end
  end
end
