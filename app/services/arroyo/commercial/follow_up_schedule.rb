class Arroyo::Commercial::FollowUpSchedule
  EXCLUDED_LABELS = %w[no-contactar venta-cancelada venta-perdida].freeze

  pattr_initialize [:opportunity!]

  def enroll(at:, actor: nil)
    return unless enrollable?

    number = opportunity.events.where(kind: 'follow_up_enrolled').count + 1
    import_legacy(at) if number == 1 && legacy_history?
    opportunity.events.create!(kind: 'follow_up_enrolled', source_key: "follow_up:enrolled:#{number}",
                               occurred_at: at, origin: 'user', actor: actor)
    conversation.add_labels(['seguimiento']) unless conversation.label_list.include?('seguimiento')
  end

  def stop(at:, actor: nil)
    return unless running?

    opportunity.events.create!(kind: 'follow_up_stopped', source_key: "follow_up:stopped:#{enrollment.id}",
                               occurred_at: at, origin: actor ? 'user' : 'system', actor: actor)
  end

  def reschedule(date:, actor: nil)
    raise Arroyo::Commercial::Error, 'not_eligible' unless active? && next_at
    raise Arroyo::Commercial::Error, 'invalid_date' unless date > local_date(Time.current)

    opportunity.events.create!(kind: 'follow_up_rescheduled', source_key: "follow_up:rescheduled:#{Time.current.to_f}",
                               occurred_at: Time.current, origin: 'user', actor: actor, data: { 'date' => date.iso8601 })
  end

  def active?
    running? && conversation.label_list.include?('seguimiento')
  end

  def enrolled_at
    enrollment&.occurred_at
  end

  def allowed?
    active? && restriction.nil?
  end

  # Por qué un seguimiento inscripto no sale: la primera condición de elegibilidad que no se cumple.
  def blocked_reason
    active? ? restriction : 'not_enrolled'
  end

  def next_at
    return unless enrollment && sent_count < 3
    return if legacy_count.positive? && last_sent_at.nil?

    date = rescheduled_date || calendar_date
    zone.local(date.year, date.month, date.day, 10)
  end

  def due?(at = Time.current)
    date = next_at
    allowed? && date.present? && date <= at && date.in_time_zone(zone).to_date == at.in_time_zone(zone).to_date
  end

  def finish_due?(at = Time.current)
    allowed? && sent_count >= 3 && last_sent_at.present? &&
      at.in_time_zone(zone).to_date > enrollment.occurred_at.in_time_zone(zone).to_date &&
      (at.in_time_zone(zone).to_date - last_sent_at.in_time_zone(zone).to_date).to_i >= 2
  end

  def sent_count
    legacy_count + opportunity.commercial_messages.size
  end

  def complete
    conversation.with_lock do
      opportunity.reload
      next false unless finish_due?

      labels = conversation.label_list - ['seguimiento']
      labels |= ['inactivo'] if opportunity.reload.effective_state == 'inactive'
      stop(at: Time.current)
      conversation.update!(label_list: labels)
      true
    end
  end

  def last_sent_at
    [opportunity.commercial_messages.map(&:created_at).max, legacy_last_at].compact.max
  end

  def steps
    sent = opportunity.events.select { |event| event.kind == 'commercial_follow_up' }
    (1..3).map { |step| step_json(step, sent.find { |event| event.data['arroyo_step'].to_i == step }&.message) }
  end

  def finished_at
    opportunity.events.select { |event| event.kind == 'follow_up_stopped' }.max_by(&:id)&.occurred_at
  end

  def as_json
    { enrolled_at: enrollment&.occurred_at&.iso8601, active: active?, sent_count: sent_count,
      last_sent_at: last_sent_at&.iso8601, next_at: next_at&.iso8601, due: due?, finish_due: finish_due? }
  end

  private

  def restriction
    labels = conversation.label_list + conversation.contact.label_list
    return 'terminal' if opportunity.terminal?
    return 'channel' unless whatsapp?
    return 'contact_blocked' if conversation.contact.blocked?
    return 'excluded_label' if labels.intersect?(EXCLUDED_LABELS)

    'no_seller' unless seller_ids.include?(conversation.assignee_id) && opportunity.assignee_id == conversation.assignee_id
  end

  def calendar_date
    date = local_date(enrollment.occurred_at) + 1
    date = [date, local_date(last_sent_at) + 2].max if last_sent_at
    date.sunday? ? date + 1 : date
  end

  # Una fecha elegida a mano vale hasta que sale el mensaje que reemplaza.
  def rescheduled_date
    event = opportunity.events.select { |item| item.kind == 'follow_up_rescheduled' && item.id > enrollment.id }.max_by(&:id)
    return if event.nil? || (last_sent_at && last_sent_at >= event.occurred_at)

    Date.iso8601(event.data['date'])
  end

  def step_json(step, message)
    if message
      { step: step, status: message.status == 'progress' ? 'sent' : message.status, sent_at: message.created_at.iso8601, scheduled_for: nil }
    elsif step <= legacy_count
      { step: step, status: 'sent', sent_at: (legacy_last_at&.iso8601 if step == legacy_count), scheduled_for: nil }
    else
      upcoming = next_at if step == sent_count + 1
      { step: step, status: upcoming ? 'scheduled' : 'pending', sent_at: nil, scheduled_for: upcoming&.iso8601 }
    end
  end

  def enrollable?
    whatsapp? && !opportunity.terminal? && !running?
  end

  def legacy_history?
    return false if opportunity.events.exists?(kind: 'confirmed')

    first = conversation.messages.where(message_type: :incoming, private: false).minimum(:created_at)
    opportunity.coverage == 'partial' || (first && first < opportunity.started_at)
  end

  def local_date(at)
    at.in_time_zone(zone).to_date
  end

  def running?
    start = enrollment
    stopped = opportunity.events.select { |event| event.kind == 'follow_up_stopped' }.map(&:id).max
    start.present? && (stopped.nil? || stopped < start.id)
  end

  def enrollment
    opportunity.events.select { |event| event.kind == 'follow_up_enrolled' }.max_by(&:id)
  end

  def conversation
    opportunity.conversation
  end

  def zone
    ActiveSupport::TimeZone[setting.config['timezone']]
  end

  def seller_ids
    setting.section(:agent_panel)['seller_ids']
  end

  def setting
    @setting ||= Arroyo::Setting.for(opportunity.account)
  end

  def whatsapp?
    opportunity.inbox.channel_type == 'Channel::Whatsapp' && opportunity.inbox.channel.provider == 'whatsapp_cloud'
  end

  def legacy_count
    legacy_event&.data&.fetch('sent_count', 0).to_i
  end

  def legacy_last_at
    value = legacy_event&.data&.fetch('last_sent_at', nil)
    Time.iso8601(value) if value.present?
  end

  def legacy_event
    opportunity.events.find { |event| event.source_key == 'follow_up:legacy' }
  end

  def import_legacy(at)
    attrs = conversation.custom_attributes
    count = [attrs['seguimiento_envios'].to_i.clamp(0, 3) - opportunity.commercial_messages.size, 0].max
    return unless count.positive?

    date = attrs['seguimiento_ultimo_envio'].to_s
    last = zone.strptime("#{date} 10:00", '%Y-%m-%d %H:%M') if date.match?(/\A\d{4}-\d{2}-\d{2}\z/)
    opportunity.events.create!(kind: 'follow_up_legacy', source_key: 'follow_up:legacy', origin: 'backfill', occurred_at: at,
                               data: { sent_count: count, last_sent_at: last&.iso8601 })
  rescue ArgumentError
    opportunity.events.create!(kind: 'follow_up_legacy', source_key: 'follow_up:legacy', origin: 'backfill', occurred_at: at,
                               data: { sent_count: count, last_sent_at: nil })
  end
end
