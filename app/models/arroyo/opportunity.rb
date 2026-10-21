class Arroyo::Opportunity < ApplicationRecord
  STATES = %w[bot unassigned pending in_progress won lost inactive unknown].freeze
  belongs_to :account
  belongs_to :conversation
  belongs_to :contact
  belongs_to :inbox
  belongs_to :assignee, class_name: 'User', optional: true
  belongs_to :first_assignee, class_name: 'User', optional: true
  belongs_to :result_user, class_name: 'User', optional: true
  has_many :events, class_name: 'Arroyo::OpportunityEvent', dependent: :destroy, inverse_of: :opportunity
  has_one :purchase, class_name: 'Arroyo::PostSalePurchase', dependent: :nullify, inverse_of: :opportunity
  validates :state, inclusion: { in: STATES }
  validates :coverage, inclusion: { in: %w[complete partial] }
  validates :reference, :started_at, presence: true
  scope :active, -> { where.not(state: %w[won lost]) }

  def terminal?
    %w[won lost].include?(state)
  end

  def overdue?(at = Time.current)
    attention_due_at.present? && attention_due_at <= at
  end

  def commercial_messages
    events.select { |event| event.kind == 'commercial_follow_up' }.filter_map(&:message).reject(&:failed?).uniq(&:id)
  end

  def effective_state(at = Time.current)
    return state unless waiting_for_customer?

    messages = commercial_messages
    return state unless completed_delivered_sequence?(messages)

    latest = messages.max_by(&:created_at)
    return state unless silent_after?(latest)

    zone = Arroyo::Setting.for(account).config['timezone']
    (at.in_time_zone(zone).to_date - latest.created_at.in_time_zone(zone).to_date).to_i >= 2 ? 'inactive' : state
  end

  def waiting_for_customer?
    state == 'in_progress' && pending_since.nil? && first_human_at.present?
  end

  private

  def completed_delivered_sequence?(messages)
    messages.size >= 3 && messages.all? { |message| %w[delivered read].include?(message.status) }
  end

  def silent_after?(message)
    last_client_at && last_client_at < message.created_at &&
      events.none? { |event| event.kind == 'resume' && event.occurred_at > message.created_at }
  end
end
