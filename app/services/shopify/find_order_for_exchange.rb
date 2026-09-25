class Shopify::FindOrderForExchange
  ORDER_FIELDS = 'id,name,email,cancelled_at,line_items,fulfillments'.freeze

  def self.call(client:, order_number:, email:)
    return nil unless client.shopify_configured?

    name = order_number.to_s.strip
    name = "##{name}" unless name.start_with?('#')

    session = ShopifyAPI::Auth::Session.new(shop: client.shopify_shop_url, access_token: client.shopify_access_token)
    api_client = ShopifyAPI::Clients::Rest::Admin.new(session: session)

    response = api_client.get(path: 'orders', query: { name: name, status: 'any', fields: ORDER_FIELDS })
    shopify_order = Array(response.body['orders']).first
    return nil unless shopify_order
    return nil unless shopify_order['email'].to_s.casecmp(email.to_s.strip).zero?

    normalize(shopify_order)
  rescue StandardError => e
    Rails.logger.error("[Shopify::FindOrderForExchange] #{e.class} #{e.message}")
    nil
  end

  def self.normalize(shopify_order)
    fulfillment = Array(shopify_order['fulfillments']).max_by { |f| f['created_at'].to_s }

    {
      id: shopify_order['id'].to_s,
      number: shopify_order['name'],
      email: shopify_order['email'],
      cancelled: shopify_order['cancelled_at'].present?,
      fulfilled_at: fulfillment&.dig('created_at').presence && Time.parse(fulfillment['created_at']),
      items: Array(shopify_order['line_items']).map do |line_item|
        {
          sku: line_item['sku'],
          product_name: line_item['title'],
          variant_title: line_item['variant_title'],
          quantity: line_item['quantity'].to_i,
          price: line_item['price'].to_f
        }
      end
    }
  end
  private_class_method :normalize
end
