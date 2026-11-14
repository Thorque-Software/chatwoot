# Una consulta vista desde el embudo del panel: a quién le toca, en qué estado quedó y de qué anuncio vino.
# Toda la métrica va al vendedor ACTUAL: si Marcos toma una consulta de Juli, cuenta entera para Marcos
# (recibida, atendida y resultado), así las reasignaciones no duplican ni reparten consultas.
class Arroyo::Commercial::BoardRow
  # Estados del embudo, de izquierda a derecha. pending = derivada al vendedor y todavía sin respuesta.
  STAGES = %w[bot unassigned pending in_progress inactive abandoned lost won].freeze
  COUNTERS = %w[received attended pending in_progress inactive abandoned lost won].freeze

  attr_reader :record

  def initialize(record, abandonment:, now:, timezone:)
    @record = record
    @abandonment = abandonment
    @now = now
    @timezone = timezone
  end

  def self.counts(rows)
    COUNTERS.index_with do |counter|
      case counter
      when 'received' then rows.size
      when 'attended' then rows.count(&:attended?)
      else rows.count { |row| row.stage == counter }
      end
    end
  end

  # Vendedor actual (id como texto), 'bot' o 'unassigned'.
  def bucket
    return record.assignee_id.to_s if record.assignee_id

    record.state == 'bot' ? 'bot' : 'unassigned'
  end

  def seller?
    record.assignee_id.present?
  end

  # Atendida = el vendedor mandó al menos un mensaje (las automatizaciones no cuentan).
  def attended?
    record.first_human_at.present?
  end

  def stage
    @stage ||= compute_stage
  end

  def labels
    @labels ||= record.conversation.cached_label_list_array
  end

  def date
    record.started_at.in_time_zone(@timezone).to_date
  end

  def nudged?
    @abandonment.nudged?(record)
  end

  def event?(kind)
    record.events.any? { |event| event.kind == kind }
  end

  private

  def compute_stage
    return record.state if record.terminal?
    return bucket unless seller?
    return 'abandoned' if @abandonment.abandoned?(record, labels)
    return 'pending' unless attended?

    record.effective_state(@now) == 'inactive' ? 'inactive' : 'in_progress'
  end
end
