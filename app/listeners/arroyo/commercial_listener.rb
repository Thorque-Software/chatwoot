class Arroyo::CommercialListener < BaseListener
  def message_created(event)
    message = event.data[:message]
    Arroyo::Commercial::Lifecycle.new(conversation: message.conversation).message(message)
  end

  alias message_updated message_created

  def assignee_changed(event)
    Arroyo::Commercial::Lifecycle.new(conversation: event.data[:conversation])
                                 .assignment(at: event.timestamp, previous_id: event.data[:changed_attributes]&.dig('assignee_id',
                                                                                                                    0), actor: Current.user)
  end

  def conversation_updated(event)
    return unless event.data[:changed_attributes]&.key?('label_list')

    Arroyo::Commercial::Lifecycle.new(conversation: event.data[:conversation])
                                 .labels(at: event.timestamp, actor: Current.user, change: event.data[:changed_attributes]['label_list'])
  end
end
