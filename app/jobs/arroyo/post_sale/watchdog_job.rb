class Arroyo::PostSale::WatchdogJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    watched = Arroyo::FollowUp.where(status: %w[awaiting_plan scheduled queued sent]).or(Arroyo::FollowUp.where(manual_status: 'pending'))
    watched.includes(purchase: [:account, :conversation, :contact]).find_each do |follow_up|
      Arroyo::PostSale::WatchdogService.new(follow_up: follow_up).perform
    end
  end
end
