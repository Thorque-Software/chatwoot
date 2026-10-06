# Pestaña "Ventanas": conversaciones de WhatsApp cuya ventana de 24 hs cierra en las próximas horas
# o ya cerró hoy (hora del negocio). La ventana se calcula igual que Conversations::MessageWindowService.
class Arroyo::AgentPanel::WindowsFinder
  WINDOW = 24.hours
  CLOSING_SOON = 6.hours

  pattr_initialize [:filters!]

  def perform
    now = Time.current
    closes_at = window_closing_times(now)
    start_of_today = now.in_time_zone(filters.timezone).beginning_of_day
    {
      closing_soon: list(closes_at.select { |_id, time| time.between?(now, now + CLOSING_SOON) }),
      closed_today: list(closes_at.select { |_id, time| time.between?(start_of_today, now) })
    }
  end

  private

  # Último mensaje entrante de cada conversación en las últimas 48 hs, más 24 hs
  def window_closing_times(now)
    scope = Message.unscoped.joins(:inbox)
                   .where(account_id: filters.account.id, message_type: :incoming, created_at: (now - (2 * WINDOW))..now,
                          inboxes: { channel_type: 'Channel::Whatsapp' })
    scope = scope.where(inbox_id: filters.inbox_ids) if filters.inbox_ids
    scope.order(:conversation_id, created_at: :desc)
         .pluck(Arel.sql('DISTINCT ON (messages.conversation_id) messages.conversation_id'), :created_at)
         .to_h
         .transform_values { |last_incoming_at| last_incoming_at + WINDOW }
  end

  def list(closes_at)
    conversations = filters.account.conversations.where(id: closes_at.keys).where.not(status: :resolved)
                           .includes(:contact, :inbox, :assignee)
    conversations = conversations.where(assignee_id: filters.assignee_ids) if filters.assignee_ids
    Arroyo::AgentPanel::ConversationList.new(conversations.sort_by { |conversation| closes_at[conversation.id] })
                                        .as_json
                                        .map { |item| item.merge(closes_at: closes_at[item[:id]].to_i) }
  end
end
