class Arroyo::Commercial::FollowUpJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Arroyo::Setting.where("config #>> '{follow_up,enabled}' = 'true'").includes(:account).find_each do |setting|
      next unless Arroyo::Commercial::Lifecycle.enabled?(setting.account)

      Arroyo::Commercial::FollowUpDispatchService.new(account: setting.account).perform
    end
  end
end
