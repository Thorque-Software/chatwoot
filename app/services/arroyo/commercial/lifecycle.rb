class Arroyo::Commercial::Lifecycle
  attr_reader :conversation

  def initialize(conversation:)
    @conversation = Conversation.find(conversation.id)
  end

  def self.enabled?(account)
    Arroyo::Setting.for(account).section(:agent_panel)['funnel_enabled'] == true
  end

  def message(record)
    return unless track_message?(record)

    conversation.with_lock do
      opportunity = message_opportunity(record)
      opportunity ||= create_opportunity(record.created_at) if record.incoming? && !sold?
      next unless opportunity

      opportunity.with_lock do
        record_message(opportunity, record)
        Arroyo::Commercial::FollowUpFailureService.new(opportunity: opportunity, message: record).perform
        refresh_attention(opportunity)
      end
    end
  end

  def assignment(at:, previous_id:, actor:)
    return unless self.class.enabled?(conversation.account)

    conversation.with_lock do
      opportunity = current
      next if opportunity.nil? || opportunity.terminal?

      opportunity.with_lock do
        record_event(opportunity, kind: 'assigned', key: "assignment:#{at.to_f}:#{conversation.assignee_id}", at: at, actor: actor,
                                  data: { from: previous_id, to: conversation.assignee_id })
        opportunity.update!(assignment_attributes(opportunity, at))
        refresh_attention(opportunity)
      end
    end
  end

  def start!(request_key:, user:, product: nil)
    raise Arroyo::Commercial::Error, 'request_key' if request_key.blank? || request_key.length > 200

    conversation.with_lock do
      existing = Arroyo::Opportunity.find_by(account: conversation.account, request_key: request_key)
      if existing
        raise Arroyo::Commercial::Error, 'request_key' if existing.conversation_id != conversation.id

        next existing
      end
      next current unless current.nil? || current.terminal?

      interrupt_previous_post_sale
      opportunity = create_opportunity(Time.current, request_key: request_key, product: product)
      record_event(opportunity, kind: 'confirmed', key: "confirmed:#{request_key}", at: opportunity.started_at, actor: user)
      opportunity
    end
  end

  def outcome(opportunity, outcome:, user:, product: nil)
    raise Arroyo::Commercial::Error, 'outcome' unless %w[won lost resume].include?(outcome)

    conversation.with_lock do
      opportunity.with_lock do
        next opportunity if opportunity.state == outcome
        raise Arroyo::Commercial::Error, 'superseded' if current&.id != opportunity.id
        raise Arroyo::Commercial::Error, 'outcome' if opportunity.state == 'won'

        apply_outcome(opportunity, outcome, user, product)
        record_event(opportunity, kind: outcome, key: "#{outcome}:#{opportunity.updated_at.to_f}", at: Time.current, actor: user)
        register_sale(opportunity) if outcome == 'won'
        opportunity
      end
    end
  end

  def labels(actor:, change:, at: Time.current, **_context)
    return unless self.class.enabled?(conversation.account)

    Arroyo::Commercial::FollowUpEnrollment.new(conversation: conversation).labels(change: change, at: at, actor: actor)
    opportunity = current
    return if opportunity.nil? || opportunity.terminal?

    result = label_outcome(Array(change.last) - Array(change.first))
    outcome(opportunity, outcome: result, user: actor || conversation.assignee) if result
  end

  def current
    Arroyo::Opportunity.where(account: conversation.account, conversation: conversation).order(started_at: :desc, id: :desc).first
  end

  private

  def track_message?(record)
    self.class.enabled?(conversation.account) && !record.private? && !record.activity?
  end

  def label_outcome(added)
    return 'won' if added.include?(Arroyo::Setting.for(conversation.account).section(:post_sale)['trigger_label'])

    'lost' if added.include?('venta-perdida')
  end

  def assignment_attributes(opportunity, at)
    { assignee: conversation.assignee, first_assignee_id: opportunity.first_assignee_id || conversation.assignee_id,
      ownership_started_at: at, pending_since: opportunity.pending_since || (at unless opportunity.first_human_at) }
  end

  def apply_outcome(opportunity, outcome, user, product)
    if outcome == 'resume'
      opportunity.update!(state: opportunity.first_human_at ? 'in_progress' : 'pending', outcome_at: nil, result_user: nil)
    else
      owner = opportunity.assignee || user
      opportunity.update!(state: outcome, result_user: owner, assignee: owner, outcome_at: Time.current,
                          product: product.presence || opportunity.product)
    end
  end

  def message_opportunity(record)
    scope = Arroyo::Opportunity.where(account: conversation.account, conversation: conversation)
    reference = record.content_attributes['arroyo_opportunity_reference']
    return scope.find_by(reference: reference) if reference.present?

    existing = Arroyo::OpportunityEvent.where(opportunity_id: scope.select(:id), message_id: record.id).first
    return existing.opportunity if existing

    latest = current
    return latest if latest.nil? || record.created_at >= latest.started_at

    nil
  end

  def create_opportunity(at, **attributes)
    opportunity = Arroyo::Opportunity.create!(account: conversation.account, conversation: conversation, contact: conversation.contact,
                                              inbox: conversation.inbox, assignee: conversation.assignee,
                                              first_assignee: conversation.assignee, ownership_started_at: conversation.assignee_id ? at : nil,
                                              reference: SecureRandom.uuid, started_at: at,
                                              state: initial_state, pending_since: conversation.assignee_id ? at : nil, **attributes)
    record_event(opportunity, kind: 'received', key: 'received', at: at)
    if conversation.assignee_id
      record_event(opportunity, kind: 'assigned', key: 'initial_assignment', at: at,
                                data: { from: nil, to: conversation.assignee_id })
    end
    refresh_attention(opportunity)
    opportunity
  end

  def initial_state
    return 'pending' if conversation.assignee_id

    conversation.pending? || conversation.assignee_agent_bot_id ? 'bot' : 'unassigned'
  end

  def record_message(opportunity, record)
    record_event(opportunity, kind: message_kind(record), key: "message:#{record.id}", at: record.created_at,
                              actor: record.sender_type == 'User' ? record.sender : nil, message: record,
                              data: record.content_attributes.slice('arroyo_step', 'arroyo_opportunity_reference'))
    record_post_sale_reply(opportunity, record) if record.incoming?
  end

  def message_kind(record)
    return 'incoming' if record.incoming?
    return record.content_attributes['arroyo_kind'] if record.content_attributes['arroyo_kind'].present?

    human_message?(record) ? 'human' : 'automatic'
  end

  def human_message?(record)
    record.sender_type == 'User' && config['seller_ids'].include?(record.sender_id) && Current.executed_by.nil? &&
      record.content_attributes['automation_rule_id'].blank?
  end

  def record_post_sale_reply(opportunity, record)
    previous = Arroyo::FollowUp.joins(:purchase).where(arroyo_post_sale_purchases: { conversation_id: conversation.id })
                               .where.not(message_id: nil).where('attempted_at <= ?', record.created_at).order(attempted_at: :desc).first
    return unless previous

    record_event(opportunity, kind: 'post_sale_reply', key: "post_sale_reply:#{previous.id}", at: record.created_at, message: record)
  end

  def refresh_attention(opportunity)
    Arroyo::Commercial::AttentionService.new(opportunity: opportunity).perform
  end

  def record_event(opportunity, kind:, key:, at:, **context)
    opportunity.events.find_or_create_by!(source_key: key) do |event|
      event.assign_attributes(kind: kind, occurred_at: at, actor: context[:actor], message: context[:message], data: context.fetch(:data, {}),
                              origin: event_origin(context[:actor]))
    end
  end

  def event_origin(actor)
    return 'automation' if Current.executed_by

    actor ? 'user' : 'system'
  end

  def interrupt_previous_post_sale
    purchases = Arroyo::PostSalePurchase.where(account: conversation.account, conversation: conversation)
    Arroyo::FollowUp.where(purchase: purchases, status: %w[awaiting_plan scheduled]).find_each do |follow_up|
      follow_up.update!(status: 'cancelled', cancellation_reason: 'new_opportunity')
    end
  end

  def register_sale(opportunity)
    unless sold?
      conversation.update!(label_list: conversation.label_list | [Arroyo::Setting.for(conversation.account).section(:post_sale)['trigger_label']])
    end
    return unless Arroyo::Setting.for(conversation.account).feature_enabled?(:post_sale)

    Arroyo::PostSale::RegisterPurchaseService.new(conversation: conversation, timestamp: opportunity.outcome_at).perform
  end

  def sold?
    conversation.label_list.include?(Arroyo::Setting.for(conversation.account).section(:post_sale)['trigger_label'])
  end

  def config
    Arroyo::Setting.for(conversation.account).section(:agent_panel)
  end
end
