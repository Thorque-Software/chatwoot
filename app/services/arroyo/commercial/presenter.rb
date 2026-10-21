class Arroyo::Commercial::Presenter
  def initialize(records, now: Time.current)
    @records = records
    @now = now
  end

  def as_json(*)
    @records.map { |record| opportunity_json(record) }
  end

  private

  def serialized_conversations
    @serialized_conversations ||= begin
      conversations = @records.map(&:conversation).uniq(&:id)
      Arroyo::AgentPanel::ConversationList.new(conversations).as_json.index_by { |item| item[:id] }
    end
  end

  def opportunity_json(record)
    { id: record.id, reference: record.reference, started_at: record.started_at.iso8601,
      state: record.effective_state(@now), overdue: record.overdue?(@now), coverage: record.coverage,
      first_human_at: record.first_human_at&.iso8601, pending_since: record.pending_since&.iso8601,
      attention_due_at: record.attention_due_at&.iso8601, product: record.product,
      assignee: assignee_json(record), conversation: serialized_conversations[record.conversation_id] }
  end

  def assignee_json(record)
    record.assignee && { id: record.assignee_id, name: record.assignee.available_name }
  end
end
