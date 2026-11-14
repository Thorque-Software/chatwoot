require 'rails_helper'

RSpec.describe Arroyo::Commercial::WindowNudgeSchedule do
  let(:zone) { ActiveSupport::TimeZone['America/Argentina/Buenos_Aires'] }
  let(:config) { Arroyo::FunnelBoardConfig::DEFAULTS['window_nudge'] }
  let(:schedule) { described_class.new(config: config, timezone: zone) }

  def local(text)
    zone.parse(text)
  end

  describe '#target' do
    it 'sends in the morning when the window lasts until the next morning' do
      expect(schedule.target(local('2026-11-10 15:00'))).to eq(local('2026-11-11 08:30'))
    end

    it 'sends the evening before when the window closes before the morning' do
      expect(schedule.target(local('2026-11-10 05:00'))).to eq(local('2026-11-10 19:00'))
    end

    it 'moves a Sunday morning to Saturday evening' do
      expect(schedule.target(local('2026-11-14 15:00'))).to eq(local('2026-11-14 19:00'))
    end

    it 'gives up when the only slots fall on Sunday or before the client wrote' do
      expect(schedule.target(local('2026-11-15 03:00'))).to be_nil
    end

    it 'keeps the margin before the window closes' do
      expect(schedule.target(local('2026-11-10 08:50'))).to eq(local('2026-11-10 19:00'))
      expect(schedule.target(local('2026-11-10 09:00'))).to eq(local('2026-11-11 08:30'))
    end

    it 'can send on Sundays when configured' do
      sundays = described_class.new(config: config.merge('skip_sundays' => false), timezone: zone)
      expect(sundays.target(local('2026-11-14 15:00'))).to eq(local('2026-11-15 08:30'))
    end
  end

  describe '#due?' do
    let(:client) { local('2026-11-10 15:00') }

    it 'is due from the target time while the window is open' do
      seller = local('2026-11-10 16:00')
      expect(schedule.due?(client, now: local('2026-11-11 08:15'), since: seller)).to be(false)
      expect(schedule.due?(client, now: local('2026-11-11 08:30'), since: seller)).to be(true)
      expect(schedule.due?(client, now: local('2026-11-11 14:45'), since: seller)).to be(false)
    end

    it 'waits an hour after a late seller message' do
      seller = local('2026-11-11 10:00')
      expect(schedule.due?(client, now: local('2026-11-11 10:30'), since: seller)).to be(false)
      expect(schedule.due?(client, now: local('2026-11-11 11:00'), since: seller)).to be(true)
    end

    it 'never sends outside the sending hours' do
      night_client = local('2026-11-10 21:00')
      expect(schedule.due?(night_client, now: local('2026-11-11 07:00'), since: local('2026-11-10 21:10'))).to be(false)
      expect(schedule.due?(night_client, now: local('2026-11-11 08:30'), since: local('2026-11-10 21:10'))).to be(true)
    end
  end
end
