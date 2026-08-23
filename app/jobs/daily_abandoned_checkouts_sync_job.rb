class DailyAbandonedCheckoutsSyncJob < ApplicationJob
  queue_as :default

  def perform
    Client.where(active: true).find_each do |client|
      next unless client.shopify_configured?

      AbandonedCheckoutsSyncJob.perform_later(client.id)
    end
  end
end
