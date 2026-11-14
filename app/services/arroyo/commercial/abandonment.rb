# Consulta abandonada: se le mandó el aviso antes de que cierre la ventana y pasaron abandon_hours (corridas) sin que
# el vendedor respondiera, y no tiene una etiqueta excluida (seguimiento...). Se calcula al leer: si el vendedor vuelve
# a escribir o le ponen seguimiento, deja de estar abandonada sin que haya que guardar nada.
# Usa los eventos ya cargados de la oportunidad (Query#records hace includes(events: :message)).
class Arroyo::Commercial::Abandonment
  def initialize(board:, now: Time.current)
    @board = board
    @now = now
  end

  def abandoned?(opportunity, labels)
    nudge = last_nudge(opportunity)
    return false if nudge.nil? || opportunity.terminal? || labels.intersect?(@board['window_nudge']['skip_labels'])
    return false if replied_after?(opportunity, nudge.occurred_at)

    @now >= nudge.occurred_at + @board['abandon_hours'].to_i.hours
  end

  # Se mandó el aviso y todavía no pasaron las horas, o el vendedor ya respondió.
  def nudged?(opportunity)
    last_nudge(opportunity).present?
  end

  private

  def last_nudge(opportunity)
    opportunity.events.select { |event| event.kind == Arroyo::Commercial::WindowNudgeService::KIND }.max_by(&:occurred_at)
  end

  def replied_after?(opportunity, at)
    opportunity.events.any? do |event|
      event.kind == 'human' && event.occurred_at > at && event.message && !event.message.failed?
    end
  end
end
