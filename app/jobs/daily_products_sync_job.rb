class DailyProductsSyncJob < ApplicationJob
  queue_as :default

  def perform
    Client.where(active: true).find_each do |client|
      next unless client.shopify_configured?

      ProductsSyncJob.perform_later(action: 'sync_all_products', client_id: client.id)
    end
  end
end
