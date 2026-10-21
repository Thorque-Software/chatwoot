require 'rails_helper'

RSpec.describe Arroyo::Commercial::BusinessCalendar do
  let(:zone) { ActiveSupport::TimeZone['America/Argentina/Buenos_Aires'] }
  let(:calendar) { described_class.new(timezone: zone, hours: 4) }

  it 'pauses at lunch instead of counting four wall-clock hours' do
    expect(calendar.deadline(zone.parse('2026-10-20 11:00'))).to eq(zone.parse('2026-10-20 19:30'))
  end

  it 'pauses overnight and Sunday' do
    expect(calendar.deadline(zone.parse('2026-10-17 19:30'))).to eq(zone.parse('2026-10-19 11:30'))
  end
end
