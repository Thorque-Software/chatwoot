# Cuándo mandar el aviso antes de que cierre la ventana de 24 h, en horario normal:
#  - si la ventana dura hasta la mañana del día en que cierra, el aviso sale esa mañana (morning_time);
#  - si cierra antes, sale el día anterior a más tardar a la tarde (evening_time);
#  - los domingos no se manda (skip_sundays) y siempre queda un margen antes del cierre.
# Si el horario elegido ya pasó (el vendedor escribió tarde), el aviso sale una hora después del último mensaje del
# vendedor, dentro del horario permitido y antes del cierre. Si no queda ningún momento válido, no se manda.
class Arroyo::Commercial::WindowNudgeSchedule
  WINDOW = 24.hours
  # Para no escribirle al cliente enseguida de que el vendedor le escribió.
  MIN_GAP = 1.hour

  def initialize(config:, timezone:)
    @config = config
    @zone = timezone
  end

  def closes_at(last_client_at)
    last_client_at + WINDOW
  end

  # Último momento en que se puede mandar el aviso de una ventana.
  def deadline(last_client_at)
    closes_at(last_client_at) - @config['margin_minutes'].to_i.minutes
  end

  # Horario ideal del aviso; nil si la ventana no deja ninguno.
  def target(last_client_at)
    limit = deadline(last_client_at)
    close_day = limit.in_time_zone(@zone).to_date
    candidates(close_day).find { |slot| slot <= limit && slot > last_client_at && allowed_day?(slot) }
  end

  # ¿Hay que mandarlo ahora? `since` es el momento desde el que el aviso tiene sentido (último mensaje del vendedor).
  def due?(last_client_at, now:, since:)
    slot = target(last_client_at)
    return false if slot.nil? || now > deadline(last_client_at)

    now >= [slot, since + MIN_GAP].max && sending_hours?(now)
  end

  def sending_hours?(time)
    local = time.in_time_zone(@zone)
    allowed_day?(local) && local >= at(local.to_date, 'morning_time') && local <= at(local.to_date, 'evening_time')
  end

  private

  # Mañana del día de cierre, tarde del día anterior, y así hacia atrás (para saltear domingos).
  def candidates(close_day)
    (0..2).flat_map { |back| [at(close_day - back, 'morning_time'), at(close_day - back - 1, 'evening_time')] }
  end

  def allowed_day?(time)
    !(@config['skip_sundays'] && time.in_time_zone(@zone).sunday?)
  end

  def at(date, key)
    hour, minute = @config[key].split(':').map(&:to_i)
    @zone.local(date.year, date.month, date.day, hour, minute)
  end
end
