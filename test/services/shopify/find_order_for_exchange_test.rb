require 'test_helper'

class Shopify::FindOrderForExchangeTest < ActiveSupport::TestCase
  def build_client
    Client.create!(
      name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com",
      shopify_shop_url: 'loja-teste.myshopify.com', shopify_access_token: 'token123'
    )
  end

  class FakeRestClient
    def initialize(orders)
      @orders = orders
    end

    def get(path:, query:)
      raise "unexpected path #{path}" unless path == 'orders'
      raise "expected name query, got #{query}" unless query[:name]

      OpenStruct.new(body: { 'orders' => @orders })
    end
  end

  def shopify_order(overrides = {})
    {
      'id' => 555_001, 'name' => '#1001', 'email' => 'ana@example.com', 'cancelled_at' => nil,
      'fulfillments' => [{ 'created_at' => '2026-09-01T10:00:00-03:00' }],
      'line_items' => [
        { 'sku' => 'SKU-1', 'title' => 'Camiseta', 'variant_title' => 'P', 'quantity' => 2, 'price' => '99.90' }
      ]
    }.merge(overrides)
  end

  test 'returns the normalized order when the number and e-mail match' do
    fake = FakeRestClient.new([shopify_order])

    ShopifyAPI::Clients::Rest::Admin.stub :new, fake do
      result = Shopify::FindOrderForExchange.call(client: build_client, order_number: '1001', email: 'ANA@example.com')

      assert_equal '555001', result[:id]
      assert_equal '#1001', result[:number]
      assert_equal false, result[:cancelled]
      assert_equal Time.parse('2026-09-01T10:00:00-03:00'), result[:fulfilled_at]
      assert_equal 1, result[:items].size
      assert_equal 'SKU-1', result[:items].first[:sku]
      assert_equal 2, result[:items].first[:quantity]
      assert_equal 99.90, result[:items].first[:price]
    end
  end

  test 'accepts an order_number already prefixed with #' do
    fake = FakeRestClient.new([shopify_order])

    ShopifyAPI::Clients::Rest::Admin.stub :new, fake do
      result = Shopify::FindOrderForExchange.call(client: build_client, order_number: '#1001', email: 'ana@example.com')
      assert_equal '#1001', result[:number]
    end
  end

  test 'returns nil when the e-mail does not match' do
    fake = FakeRestClient.new([shopify_order])

    ShopifyAPI::Clients::Rest::Admin.stub :new, fake do
      assert_nil Shopify::FindOrderForExchange.call(client: build_client, order_number: '1001', email: 'outro@example.com')
    end
  end

  test 'returns nil when no order is found' do
    fake = FakeRestClient.new([])

    ShopifyAPI::Clients::Rest::Admin.stub :new, fake do
      assert_nil Shopify::FindOrderForExchange.call(client: build_client, order_number: '9999', email: 'ana@example.com')
    end
  end

  test 'marks cancelled orders' do
    fake = FakeRestClient.new([shopify_order('cancelled_at' => '2026-09-02T09:00:00-03:00')])

    ShopifyAPI::Clients::Rest::Admin.stub :new, fake do
      result = Shopify::FindOrderForExchange.call(client: build_client, order_number: '1001', email: 'ana@example.com')
      assert_equal true, result[:cancelled]
    end
  end

  test 'returns nil without raising when the client has no Shopify credentials' do
    client = Client.create!(name: 'Sem Shopify', email: "sem-shopify-#{SecureRandom.hex(4)}@example.com")
    assert_nil Shopify::FindOrderForExchange.call(client: client, order_number: '1001', email: 'ana@example.com')
  end

  test 'returns nil without raising when the API call errors' do
    fake_class = Class.new { def get(*) = raise(StandardError, 'boom') }

    ShopifyAPI::Clients::Rest::Admin.stub :new, fake_class.new do
      assert_nil Shopify::FindOrderForExchange.call(client: build_client, order_number: '1001', email: 'ana@example.com')
    end
  end

  test 'returns nil without raising when the order has no fulfillment yet' do
    fake = FakeRestClient.new([shopify_order('fulfillments' => [])])

    ShopifyAPI::Clients::Rest::Admin.stub :new, fake do
      result = Shopify::FindOrderForExchange.call(client: build_client, order_number: '1001', email: 'ana@example.com')
      assert_nil result[:fulfilled_at]
    end
  end
end
