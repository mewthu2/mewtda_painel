class RefundsSyncJob < ApplicationJob
  queue_as :default

  def perform(client_id:, processed_at_min:, processed_at_max:)
    client = Client.find(client_id)
    return unless client.active? && client.shopify_configured?

    session = ShopifyAPI::Auth::Session.new(
      shop: client.shopify_shop_url,
      access_token: client.shopify_access_token
    )

    Shopify::Orders.sync_refunds_to_rails(
      session: session,
      client: client,
      processed_at_min: processed_at_min,
      processed_at_max: processed_at_max
    )
  rescue StandardError => e
    Rails.logger.error "[RefundsSyncJob] Falha para client #{client_id}: #{e.message}"
  end
end
