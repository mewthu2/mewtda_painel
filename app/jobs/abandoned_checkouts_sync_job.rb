class AbandonedCheckoutsSyncJob < ApplicationJob
  queue_as :default

  def perform(client_id)
    client = Client.find(client_id)
    return unless client.active? && client.shopify_configured?

    session = ShopifyAPI::Auth::Session.new(shop: client.shopify_shop_url, access_token: client.shopify_access_token)
    Shopify::Checkouts.sync_abandoned_checkouts_to_rails(session: session, client: client)
  rescue StandardError => e
    Rails.logger.error "[AbandonedCheckoutsSyncJob] Falha para client #{client_id}: #{e.message}"
  end
end
