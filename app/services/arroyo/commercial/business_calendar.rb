class Arroyo::Commercial::BusinessCalendar
  WINDOWS = [[8, 30, 12, 0], [16, 30, 20, 30]].freeze

  def initialize(timezone:, hours: 4)
    @timezone = timezone
    @seconds = hours.hours.to_i
  end

  def deadline(started_at)
    cursor = started_at.in_time_zone(@timezone)
    remaining = @seconds
    loop do
      unless cursor.sunday?
        WINDOWS.each do |start_hour, start_minute, end_hour, end_minute|
          first = cursor.change(hour: start_hour, min: start_minute, sec: 0)
          last = cursor.change(hour: end_hour, min: end_minute, sec: 0)
          next if cursor >= last

          cursor = [cursor, first].max
          available = (last - cursor).to_i
          return cursor + remaining if remaining <= available

          remaining -= available
          cursor = last
        end
      end
      cursor = (cursor.to_date + 1).in_time_zone(@timezone)
    end
  end
end
