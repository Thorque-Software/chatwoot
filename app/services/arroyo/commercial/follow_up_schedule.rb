class Arroyo::Commercial::FollowUpSchedule
  pattr_initialize [:opportunity!]

  def enroll(at:, manual: false, actor: nil)
    return unless enrollable?(manual)

    number = opportunity.events.where(kind: 'follow_up_enrolled').count + 1
    import_legacy(at) if number == 1 && legacy_history?
    opportunity.events.create!(kind: 'follow_up_enrolled', source_key: "follow_up:enrolled:#{number}",
                               occurred_at: at, origin: manual ? 'user' : 'system', actor: actor)
    conversation.add_labels(['seguimiento']) unless conversation.label_list.include?('seguimiento')
  end

  def stop(at:, actor: nil)
    return unless running?

    opportunity.events.create!(kind: 'follow_up_stopped', source_key: "follow_up:stopped:#{enrollment.id}",
                               occurred_at: at, origin: actor ? 'user' : 'system', actor: actor)
  end

  def active?
    running? && conversation.label_list.include?('seguimiento')
  end

  def allowed?
    labels = conversation.label_list + conversation.contact.label_list
    active? && !opportunity.terminal? && whatsapp? && !conversation.contact.blocked? &&
      !labels.intersect?(%w[no-contactar venta-cancelada venta-perdida]) &&
      seller_ids.include?(conversation.assignee_id) && opportunity.assignee_id == conversation.assignee_id
  end

  def next_at
    return unless enrollment && sent_count < 3
    return if legacy_count.positive? && last_sent_at.nil?

    date = local_date(enrollment.occurred_at) + 1
    date = [date, local_date(last_sent_at) + 2].max if last_sent_at
    date += 1 if date.sunday?
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

  def as_json
    { enrolled_at: enrollment&.occurred_at&.iso8601, active: active?, sent_count: sent_count,
      last_sent_at: last_sent_at&.iso8601, next_at: next_at&.iso8601, due: due?, finish_due: finish_due? }
  end

  private

  def enrollable?(manual)
    return false unless whatsapp? && !opportunity.terminal?
    return false if !manual && conversation.custom_attributes['arroyo_follow_up_stopped_at'].present?

    enrollment.nil? || (manual && !running?)
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
