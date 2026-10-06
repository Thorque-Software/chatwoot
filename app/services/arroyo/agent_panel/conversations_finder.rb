# Drill-down: conversaciones detrás de una métrica, con los mismos filtros del panel.
class Arroyo::AgentPanel::ConversationsFinder
  LIMIT = 500

  pattr_initialize [:filters!]

  def perform
    ids = conversation_ids
    conversations = filters.account.conversations.where(id: ids).includes(:contact, :inbox, :assignee)
                           .order(last_activity_at: :desc).limit(LIMIT)
    { count: ids.size, conversations: Arroyo::AgentPanel::ConversationList.new(conversations).as_json }
  end

  private

  def conversation_ids
    case filters.metric
    when 'conversations_attended', 'messages_sent'
      Arroyo::AgentPanel::Scopes.messages(filters).distinct.pluck(:conversation_id)
    when 'assignments'
      Arroyo::AgentPanel::Scopes.assignments(filters).distinct.pluck(:conversation_id)
    when 'first_response_median'
      Arroyo::AgentPanel::Scopes.first_responses(filters).distinct.pluck(:conversation_id)
    when 'windows_closed'
      Arroyo::AgentPanel::Scopes.label_taggings(filters, Arroyo::WINDOW_CLOSED_LABEL).distinct.pluck(:taggable_id)
    when 'sales'
      Arroyo::AgentPanel::Scopes.label_taggings(filters, filters.sale_label).distinct.pluck(:taggable_id)
    end
  end
end
