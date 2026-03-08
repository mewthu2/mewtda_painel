class ProductsSyncJob < ApplicationJob
  queue_as :default

  def perform(action:)
    case action
    when 'sync_all_products'
      sync_all_products
    else
      Rails.logger.error "[ProductsSyncJob] Ação desconhecida: #{action}"
    end
  end

  ############################################
  # CLIENT SHOPIFY
  ############################################

  def client_shopify_rest
    session = ShopifyAPI::Auth::Session.new(
      shop: ENV.fetch('HENRRI_SHOP_URL'),
      access_token: ENV.fetch('HENRRI_OAUTH_SECRET')
    )

    ShopifyAPI::Clients::Rest::Admin.new(session:)
  end

  ############################################
  # SYNC PRODUTOS COM PAGINAÇÃO
  ############################################

  def sync_all_products
    Rails.logger.info "[ProductsSyncJob] Iniciando sincronização de produtos"

    client = client_shopify_rest

    response = client.get(
      path: 'products',
      query: { limit: 250 }
    )

    process_products(response.body['products'])

    loop do
      next_page_info = response.next_page_info
      break unless next_page_info

      response = client.get(
        path: 'products',
        query: {
          limit: 250,
          page_info: next_page_info
        }
      )

      process_products(response.body['products'])
    end

    Rails.logger.info "[ProductsSyncJob] Sincronização finalizada"
  end

  ############################################
  # PROCESSA PRODUTOS
  ############################################

  def process_products(products)
    products.each do |shopify_product|
      shopify_product['variants'].each do |variant|
        product = Product.find_or_initialize_by(
          shopify_variant_id: variant['id'].to_s
        )

        product.assign_attributes(
          sku: variant['sku'],
          shopify_product_id: shopify_product['id'].to_s,
          shopify_variant_id: variant['id'].to_s,
          shopify_inventory_item_id: variant['inventory_item_id'].to_s,
          shopify_product_name: shopify_product['title'],
          price: variant['price'],
          compare_at_price: variant['compare_at_price'],
          vendor: shopify_product['vendor'],
          option1: variant['option1'],
          option2: variant['option2'],
          option3: variant['option3'],
          tags: shopify_product['tags'],
          image_url: shopify_product.dig('image', 'src')
        )

        product.save!

        Rails.logger.info "[ProductsSyncJob] Produto sincronizado SKU #{product.sku}"
      end
    end
  end
end