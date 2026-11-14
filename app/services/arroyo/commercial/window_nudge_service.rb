# Aviso antes de que cierre la ventana de 24 h: un mensaje de texto libre (la ventana sigue abierta) para el cliente
# que no le contestó al vendedor. Uno solo por ventana, en el horario de WindowNudgeSchedule, y nunca a
# conversaciones con etiquetas excluidas, vendidas o perdidas. Sale marcado con arroyo_kind para que no cuente
# como atención del vendedor ni lo tome el bot de n8n (que solo responde entrantes en conversaciones pending).
class Arroyo::Commercial::WindowNudgeService
  KIND = 'window_nudge'.freeze
  NEVER_LABELS = %w[no-contactar venta-cancelada venta-perdida].freeze

  def initialize(opportunity:, now: Time.current)
    @opportunity = opportunity
    @now = now
  end

  # Devuelve el mensaje enviado o nil si no correspondía.
  def perform
    conversation = opportunity.conversation
    conversation.reload.with_lock do
      opportunity.with_lock { create_message(conversation) if eligible?(conversation) }
    end
  end

  def eligible?(conversation)
    enabled? && waiting_for_client? && conversation_allowed?(conversation) && !already_nudged? &&
      schedule.due?(opportunity.last_client_at, now: now, since: opportunity.last_human_at)
  end

  private

  attr_reader :opportunity, :now

  def setting
    @setting ||= Arroyo::Setting.for(opportunity.account)
  end

  def board
    setting.section(:funnel_board)
  end

  def nudge_config
    board['window_nudge']
  end

  def enabled?
    board['enabled'] && nudge_config['enabled'] && Arroyo::Commercial::Lifecycle.enabled?(opportunity.account)
  end

  # El vendedor escribió último y el cliente todavía no contestó.
  def waiting_for_client?
    opportunity.state == 'in_progress' && opportunity.last_client_at.present? && opportunity.last_human_at.present? &&
      opportunity.last_human_at > opportunity.last_client_at
  end

  def conversation_allowed?(conversation)
    conversation.open? && conversation.inbox.channel_type == 'Channel::Whatsapp' && inbox_selected?(conversation) &&
      !conversation.contact.blocked? && !excluded_labels?(conversation) &&
      Arroyo::Commercial::Lifecycle.new(conversation: conversation).current&.id == opportunity.id
  end

  def inbox_selected?(conversation)
    board['inboxes'].blank? || board['inboxes'].any? { |item| item['id'] == conversation.inbox_id }
  end

  def excluded_labels?(conversation)
    excluded = nudge_config['skip_labels'] + NEVER_LABELS + setting.lost_labels + [setting.section(:post_sale)['trigger_label']]
    (conversation.label_list + conversation.contact.label_list).intersect?(excluded)
  end

  def already_nudged?
    opportunity.events.where(kind: KIND).exists?(['occurred_at > ?', opportunity.last_client_at])
  end

  def schedule
    Arroyo::Commercial::WindowNudgeSchedule.new(config: nudge_config, timezone: ActiveSupport::TimeZone[setting.config['timezone']])
  end

  def create_message(conversation)
    message = Messages::MessageBuilder.new(nil, conversation, content: content(conversation), message_type: 'outgoing', private: false,
                                                              content_attributes: { arroyo_kind: KIND,
                                                                                    arroyo_opportunity_reference: opportunity.reference }).perform
    opportunity.events.find_or_create_by!(source_key: "message:#{message.id}") do |event|
      event.assign_attributes(kind: KIND, origin: 'automation', occurred_at: message.created_at, message: message, data: {})
    end
    message
  end

  def content(conversation)
    values = {
      'contact.first_name' => first_word(conversation.contact.name),
      'contact.name' => conversation.contact.name.to_s.strip,
      'agent.first_name' => first_word(conversation.assignee&.available_name)
    }
    text = nudge_config['text'].gsub(/\{\{\s*([\w.]+)\s*\}\}/) { values.fetch(Regexp.last_match(1), '') }
    # Sin nombre queda "Hola , ¿..." : se limpia el espacio sobrante antes de la puntuación.
    text.gsub(/[ \t]+([,.!?;:])/, '\1').gsub(/[ \t]{2,}/, ' ').strip
  end

  def first_word(name)
    name.to_s.strip.split(/\s+/).first.to_s
  end
end
