class Arroyo::AssignmentListener < BaseListener
  def assignee_changed(event)
    conversation = event.data[:conversation]
    # El listener corre async: el asignado del evento sale de changed_attributes, no del registro recargado
    assignee_id = event.data[:changed_attributes]&.dig('assignee_id', 1)
    return if assignee_id.blank?

    Arroyo::AssignmentEvent.create!(
      account_id: conversation.account_id,
      conversation: conversation,
      inbox_id: conversation.inbox_id,
      assignee_id: assignee_id,
      created_at: event.timestamp
    )
  end
end
