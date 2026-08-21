class DailyOrdersSyncJob < ApplicationJob
  queue_as :default

  def perform
    Client.where(active: true).find_each do |client|
      next unless client.shopify_configured?

      OrdersUpdateJob.perform_later(
        action: 'sync_shopify_orders_routine',
        client_id: client.id,
        routine: :last_3_hours
      )
    end
  end
end
