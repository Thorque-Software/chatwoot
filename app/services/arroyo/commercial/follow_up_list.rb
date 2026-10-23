class Arroyo::Commercial::FollowUpList
  STATUSES = %w[scheduled awaiting_finish finished paused unenrolled].freeze

  pattr_initialize [:account!]

  def as_json
    rows = conversations.map { |conversation| row(conversation, latest[conversation.id]) }
    { follow_ups: rows.sort_by { |item| [item[:next_at] || 'z', item[:conversation_id]] }, totals: totals(rows), agenda: agenda(rows) }
  end

  def row_for(conversation)
    row(conversation, Arroyo::Opportunity.where(account: account, conversation: conversation).includes(events: :message).order(:id).last)
  end

  private

  def ids
    @ids ||= begin
      enrolled = Arroyo::Opportunity.where(account: account).joins(:events).where(arroyo_opportunity_events: { kind: 'follow_up_enrolled' })
      account.conversations.tagged_with('seguimiento').pluck(:id) | enrolled.distinct.pluck(:conversation_id)
    end
  end

  def latest
    @latest ||= begin
      scope = Arroyo::Opportunity.where(account: account, conversation_id: ids)
      scope.where(id: scope.select('MAX(arroyo_opportunities.id)').group(:conversation_id))
           .includes(:account, :assignee, :inbox, conversation: :contact, events: :message).index_by(&:conversation_id)
    end
  end

  def conversations
    account.conversations.where(id: ids).includes(:contact, :assignee)
  end

  def row(conversation, opportunity)
    schedule = Arroyo::Commercial::FollowUpSchedule.new(opportunity: opportunity) if opportunity
    status = status(schedule)
    enrolled = status != 'unenrolled'
    { conversation_id: conversation.display_id, contact_name: conversation.contact.name, contact_phone: conversation.contact.phone_number,
      assignee: conversation.assignee && { id: conversation.assignee_id, name: conversation.assignee.available_name },
      advisor_alias: advisor_alias(conversation, opportunity), opportunity_reference: opportunity&.reference, status: status,
      sent_count: enrolled ? schedule.sent_count : legacy_count(conversation),
      steps: enrolled ? schedule.steps : legacy_steps(conversation) }.merge(schedule_fields(schedule, status))
  end

  def schedule_fields(schedule, status)
    next_at = schedule.next_at if status == 'scheduled'
    { next_at: next_at&.iso8601, next_step: (schedule.sent_count + 1 if next_at), due_today: next_at.present? && schedule.due?,
      enrolled_at: schedule&.enrolled_at&.iso8601, finished_at: (schedule.finished_at&.iso8601 if status == 'finished'),
      blocked_reason: blocked_reason(schedule, status), can_send_now: status == 'scheduled' && schedule.allowed?,
      can_reschedule: next_at.present?, can_enroll: status == 'unenrolled' }
  end

  def status(schedule)
    return 'unenrolled' unless schedule&.enrolled_at
    return schedule.sent_count >= 3 ? 'awaiting_finish' : 'scheduled' if schedule.active?

    schedule.sent_count >= 3 ? 'finished' : 'paused'
  end

  def blocked_reason(schedule, status)
    return 'not_enrolled' if status == 'unenrolled'

    schedule.blocked_reason if %w[scheduled awaiting_finish].include?(status)
  end

  # Antes de inscribirse, lo enviado por el flujo anterior solo está en los atributos de la conversación.
  def legacy_count(conversation)
    conversation.custom_attributes['seguimiento_envios'].to_i.clamp(0, 3)
  end

  def legacy_steps(conversation)
    date = conversation.custom_attributes['seguimiento_ultimo_envio'].to_s
    last = "#{date}T10:00:00-03:00" if date.match?(/\A\d{4}-\d{2}-\d{2}\z/)
    count = legacy_count(conversation)
    (1..3).map do |step|
      { step: step, status: step <= count ? 'sent' : 'pending', sent_at: (last if step == count), scheduled_for: nil }
    end
  end

  def advisor_alias(conversation, opportunity)
    name = (opportunity&.assignee || conversation.assignee)&.available_name
    name && settings.follow_up_signature(name)
  end

  def totals(rows)
    STATUSES.index_with { |status| rows.count { |item| item[:status] == status } }
  end

  def agenda(rows)
    zone = ActiveSupport::TimeZone[settings.config['timezone']]
    rows.filter_map { |item| Time.iso8601(item[:next_at]).in_time_zone(zone).to_date if item[:next_at] }
        .tally.sort.map { |date, count| { date: date.iso8601, count: count } }
  end

  def settings
    @settings ||= Arroyo::Setting.for(account)
  end
end
