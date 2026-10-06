# Consultas base de cada métrica del panel. Las comparten el armado del reporte y el drill-down.
# Todas filtran por cuenta y rango para usar los índices (account_id, ..., created_at).
module Arroyo::AgentPanel::Scopes
  # Salientes no privados de un usuario humano: excluye bots, automatizaciones y mensajes
  # automáticos de Arroyo (que se crean con sender nil)
  def self.messages(filters)
    scope = Message.unscoped.where(account_id: filters.account.id, message_type: :outgoing, private: false,
                                   sender_type: 'User', sender_id: filters.user_ids, created_at: filters.time_range)
    filters.inbox_ids ? scope.where(inbox_id: filters.inbox_ids) : scope
  end

  def self.assignments(filters)
    scope = Arroyo::AssignmentEvent.where(account_id: filters.account.id, assignee_id: filters.user_ids, created_at: filters.time_range)
    filters.inbox_ids ? scope.where(inbox_id: filters.inbox_ids) : scope
  end

  def self.first_responses(filters)
    scope = ReportingEvent.where(account_id: filters.account.id, name: 'first_response', user_id: filters.user_ids,
                                 created_at: filters.time_range)
    filters.inbox_ids ? scope.where(inbox_id: filters.inbox_ids) : scope
  end

  # Labels aplicadas en el rango, atribuidas al asignado actual de la conversación (ver ARCHITECTURE_NOTES D8)
  def self.label_taggings(filters, label)
    scope = ActsAsTaggableOn::Tagging.joins(:tag)
                                     .joins('INNER JOIN conversations ON conversations.id = taggings.taggable_id')
                                     .where(taggable_type: 'Conversation', context: 'labels', created_at: filters.time_range,
                                            tags: { name: label })
                                     .where(conversations: { account_id: filters.account.id, assignee_id: filters.user_ids })
    filters.inbox_ids ? scope.where(conversations: { inbox_id: filters.inbox_ids }) : scope
  end
end
