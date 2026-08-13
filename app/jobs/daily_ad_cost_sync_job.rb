class DailyAdCostSyncJob < ApplicationJob
  queue_as :default

  def perform
    today = Date.current

    Client.find_each do |client|
      next unless client.meta_configured? || client.google_ads_configured?

      AdCostSyncJob.perform_later(client_id: client.id, year: today.year, month: today.month)
    end
  end
end
