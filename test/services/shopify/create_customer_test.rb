require 'test_helper'

class Shopify::CreateCustomerTest < ActiveSupport::TestCase
  def build_client
    Client.create!(
      name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com",
      shopify_shop_url: 'loja-teste.myshopify.com', shopify_access_token: 'token123'
    )
  end

  class FakeShopifyClient
    def initialize(&block)
      @block = block
    end

    def query(graphql_query)
      @block.call(graphql_query)
    end
  end

  test 'returns ok true with the customer id on success' do
    fake = FakeShopifyClient.new do |_query|
      { 'customerCreate' => { 'customer' => { 'id' => 'gid://shopify/Customer/123' }, 'userErrors' => [] } }
    end

    Shopify::Client.stub :new, fake do
      result = Shopify::CreateCustomer.new(build_client).call(name: 'Ana Silva', email: 'ana@example.com', phone: '11999998888')
      assert_equal true, result[:ok]
      assert_equal 'gid://shopify/Customer/123', result[:customer_id]
    end
  end

  test 'returns ok true with nil customer id when the e-mail is already taken' do
    fake = FakeShopifyClient.new do |query|
      if query.include?('customers(')
        { 'customers' => { 'edges' => [] } }
      else
        {
          'customerCreate' => {
            'customer' => nil,
            'userErrors' => [{ 'field' => %w[email], 'message' => 'Email has already been taken' }]
          }
        }
      end
    end

    Shopify::Client.stub :new, fake do
      result = Shopify::CreateCustomer.new(build_client).call(name: 'Ana Silva', email: 'ana@example.com', phone: '')
      assert_equal true, result[:ok]
    end
  end

  test 'returns ok false on an unexpected userError' do
    fake = FakeShopifyClient.new do |_query|
      {
        'customerCreate' => {
          'customer' => nil,
          'userErrors' => [{ 'field' => %w[phone], 'message' => 'Phone is invalid' }]
        }
      }
    end

    Shopify::Client.stub :new, fake do
      result = Shopify::CreateCustomer.new(build_client).call(name: 'Ana Silva', email: 'ana@example.com', phone: 'abc')
      assert_equal false, result[:ok]
      assert_nil result[:customer_id]
    end
  end

  test 'returns ok false without raising when the API call errors' do
    fake = FakeShopifyClient.new { |_query| raise StandardError, 'boom' }

    Shopify::Client.stub :new, fake do
      result = Shopify::CreateCustomer.new(build_client).call(name: 'Ana Silva', email: 'ana@example.com', phone: '')
      assert_equal false, result[:ok]
    end
  end

  test 'returns ok false without raising when the client has no Shopify credentials' do
    client = Client.create!(name: 'Sem Shopify', email: "sem-shopify-#{SecureRandom.hex(4)}@example.com")

    result = Shopify::CreateCustomer.new(client).call(name: 'Ana Silva', email: 'ana@example.com', phone: '')
    assert_equal false, result[:ok]
  end

  test 'safely escapes quotes in the name and email' do
    captured = nil
    fake = FakeShopifyClient.new do |query|
      captured = query
      { 'customerCreate' => { 'customer' => { 'id' => 'gid://shopify/Customer/1' }, 'userErrors' => [] } }
    end

    Shopify::Client.stub :new, fake do
      Shopify::CreateCustomer.new(build_client).call(name: 'Ana "A" Silva', email: 'ana@example.com', phone: '')
    end

    assert_includes captured, '\"A\"'
  end
end
