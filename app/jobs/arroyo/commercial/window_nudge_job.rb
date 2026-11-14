# Cada 15 minutos manda los avisos antes de que cierre la ventana de 24 h (funnel_board.window_nudge).
class Arroyo::Commercial::WindowNudgeJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    now = Time.current
    Arroyo::Setting.where("config #>> '{funnel_board,window_nudge,enabled}' = 'true'").includes(:account).find_each do |setting|
      next unless setting.section(:funnel_board)['enabled'] && Arroyo::Commercial::Lifecycle.enabled?(setting.account)

      candidates(setting.account, now).find_each do |opportunity|
        Arroyo::Commercial::WindowNudgeService.new(opportunity: opportunity, now: now).perform
      rescue StandardError => e
        Rails.logger.error "Arroyo window nudge: consulta #{opportunity.id}: #{e.class} #{e.message}"
      end
    end
  end

  private

  # Ventanas todavía abiertas donde el vendedor escribió último.
  def candidates(account, now)
    Arroyo::Opportunity.where(account: account, state: 'in_progress', last_client_at: (now - 24.hours)..now)
                       .where('last_human_at > last_client_at').includes(conversation: [:inbox, :contact, :assignee])
  end
end
