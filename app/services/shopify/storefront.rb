module Shopify
  # Cliente mínimo da Storefront API, usado pelas landing pages públicas.
  # O token da Storefront é público por design (vai pro navegador também, pro
  # botão de compra criar o carrinho direto na Shopify).
  class Storefront
    API_VERSION = '2026-07'.freeze
    CACHE_TTL = 5.minutes

    PRODUCT_QUERY = <<~GRAPHQL.freeze
      query LandingProduct($handle: String, $id: ID) {
        product(handle: $handle, id: $id) {
          id
          handle
          title
          description
          availableForSale
          featuredImage { url altText width height }
          images(first: 10) { nodes { url altText width height } }
          options { name optionValues { name } }
          variants(first: 100) {
            nodes {
              id
              title
              availableForSale
              selectedOptions { name value }
              price { amount currencyCode }
              compareAtPrice { amount currencyCode }
              image { url altText width height }
            }
          }
        }
      }
    GRAPHQL

    def self.endpoint_for(client)
      shop = client.shopify_shop_url.to_s.sub(%r{\Ahttps?://}, '').chomp('/')
      "https://#{shop}/api/#{API_VERSION}/graphql.json"
    end

    def initialize(client)
      @client = client
    end

    def configured?
      @client.storefront_configured?
    end

    def endpoint
      self.class.endpoint_for(@client)
    end

    def token
      @client.shopify_storefront_token
    end

    # ref = handle ou GID (ver LandingPage.normalize_product_ref). Retorna o
    # hash do produto (chaves string, como vem da API) ou nil se o produto não
    # existir, não estiver publicado no canal do token, ou a API falhar — a
    # página trata nil como "produto indisponível".
    def product(ref)
      return nil if ref.blank? || !configured?

      variables = ref.start_with?('gid://') ? { id: ref } : { handle: ref }
      cache_key = ['storefront-product', @client.id, ref, token.to_s.last(6)]
      Rails.cache.fetch(cache_key, expires_in: CACHE_TTL, skip_nil: true) do
        query(PRODUCT_QUERY, variables)&.dig('product')
      end
    end

    KIT_QUOTE_MUTATION = <<~GRAPHQL.freeze
      mutation KitQuote($lines: [CartLineInput!]!) {
        cartCreate(input: { lines: $lines }) {
          cart { cost { subtotalAmount { amount } totalAmount { amount } } }
          userErrors { field message }
        }
      }
    GRAPHQL
    KIT_QUOTE_TTL = 10.minutes

    # Quanto a loja cobra por 1..max unidades, já com os descontos automáticos
    # (ex.: "leve 3 com 7%"). Monta carrinhos de cotação na Storefront API —
    # sem comprador, viram só carrinhos vazios abandonados — e guarda em cache.
    # Retorna { 1 => 69.9, 2 => 132.82, ... } (BigDecimal) ou {} se falhar.
    def kit_prices(variant_id, max: 4)
      return {} if variant_id.blank? || !configured?

      cache_key = ['storefront-kit-prices', @client.id, variant_id, max, token.to_s.last(6)]
      Rails.cache.fetch(cache_key, expires_in: KIT_QUOTE_TTL, skip_nil: true) do
        prices = (1..max).to_h do |quantity|
          data = query(KIT_QUOTE_MUTATION, lines: [{ merchandiseId: variant_id, quantity: quantity }])
          [quantity, data&.dig('cartCreate', 'cart', 'cost', 'totalAmount', 'amount')&.to_d]
        end
        prices.values.all? ? prices : nil
      end || {}
    end

    def products(handles)
      Array(handles).filter_map { |handle| product(handle) }
    end

    private

    def query(graphql, variables = {})
      response = HTTParty.post(
        endpoint,
        headers: {
          'Content-Type' => 'application/json',
          'X-Shopify-Storefront-Access-Token' => token
        },
        body: { query: graphql, variables: variables }.to_json,
        timeout: 8
      )

      body = response.parsed_response
      unless response.success? && body.is_a?(Hash) && body['errors'].blank?
        Rails.logger.error("[Shopify::Storefront] client #{@client.id} HTTP #{response.code}: #{response.body.to_s.first(300)}")
        return nil
      end

      body['data']
    rescue StandardError => e
      Rails.logger.error("[Shopify::Storefront] client #{@client.id}: #{e.class} #{e.message}")
      nil
    end
  end
end
