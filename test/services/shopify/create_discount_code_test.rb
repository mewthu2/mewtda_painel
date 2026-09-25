require 'test_helper'

class Shopify::CreateDiscountCodeTest < ActiveSupport::TestCase
  def build_client
    Client.create!(
      name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com",
      shopify_shop_url: 'loja-teste.myshopify.com', shopify_access_token: 'token123'
    )
  end

  class FakeRestClient
    def initialize(&block)
      @block = block
    end

    def post(path:, body:)
      OpenStruct.new(body: @block.call(path, body))
    end
  end

  test 'creates a percentage discount and returns the code' do
    fake = FakeRestClient.new do |_path, _body|
      { 'data' => { 'discountCodeBasicCreate' => { 'codeDiscountNode' => {}, 'userErrors' => [] } } }
    end

    ShopifyAPI::Clients::Rest::Admin.stub :new, fake do
      code = Shopify::CreateDiscountCode.call(client: build_client, title: 'Troca', percentage: 10)
      assert_match(/\AREC[A-Z0-9]{8}\z/, code)
    end
  end

  test 'creates a fixed amount discount using discountAmount in the mutation' do
    captured = nil
    fake = FakeRestClient.new do |_path, body|
      captured = body
      { 'data' => { 'discountCodeBasicCreate' => { 'codeDiscountNode' => {}, 'userErrors' => [] } } }
    end

    ShopifyAPI::Clients::Rest::Admin.stub :new, fake do
      code = Shopify::CreateDiscountCode.call(client: build_client, title: 'Troca', amount: 149.9)
      assert code.present?
    end

    value = captured[:variables][:basicCodeDiscount][:customerGets][:value]
    assert_equal 149.9, value[:discountAmount][:amount]
    assert_not value.key?(:percentage)
  end

  test 'returns nil when the API returns userErrors' do
    fake = FakeRestClient.new do |_path, _body|
      { 'data' => { 'discountCodeBasicCreate' => { 'codeDiscountNode' => nil, 'userErrors' => [{ 'message' => 'boom' }] } } }
    end

    ShopifyAPI::Clients::Rest::Admin.stub :new, fake do
      assert_nil Shopify::CreateDiscountCode.call(client: build_client, title: 'Troca', amount: 50)
    end
  end
end
