require 'test_helper'

class Shopify::StorefrontTest < ActiveSupport::TestCase
  setup do
    @client = Client.create!(name: 'HENRRI', email: "loja-#{SecureRandom.hex(4)}@example.com",
                             shopify_shop_url: 'henrri.myshopify.com', shopify_storefront_token: 'public-token')
    @storefront = Shopify::Storefront.new(@client)
  end

  test 'quotes kit prices with the store automatic discounts' do
    totals = { 1 => '69.9', 2 => '132.82', 3 => '195.03', 4 => '260.04' }
    @storefront.stub :query!, ->(_q, vars) {
      qty = vars[:lines].first[:quantity]
      { 'cartCreate' => { 'cart' => { 'cost' => { 'totalAmount' => { 'amount' => totals[qty] } } }, 'userErrors' => [] } }
    } do
      prices = @storefront.kit_prices('gid://shopify/ProductVariant/1', max: 4)
      assert_equal 132.82.to_d, prices[2]
      assert_equal 260.04.to_d, prices[4]
    end
  end

  test 'returns no kit prices when the quote fails' do
    @storefront.stub :query!, ->(*) { raise Shopify::Storefront::Error, 'HTTP 500' } do
      assert_equal({}, @storefront.kit_prices('gid://shopify/ProductVariant/1'))
    end
  end

  test 'fetch_product! tells a missing product (nil) from an API failure (Error)' do
    @storefront.stub :query!, ->(*) { { 'product' => nil } } do
      assert_nil @storefront.fetch_product!('nao-existe')
    end
    @storefront.stub :query!, ->(*) { raise Shopify::Storefront::Error, 'timeout' } do
      assert_raises(Shopify::Storefront::Error) { @storefront.fetch_product!('camiseta') }
      assert_nil @storefront.product('camiseta')
    end
  end

  test 'product looks up by id for GIDs and by handle otherwise' do
    seen = []
    @storefront.stub :query!, ->(_q, vars) { seen << vars; { 'product' => { 'title' => 'X' } } } do
      @storefront.product('gid://shopify/Product/10790980190502')
      @storefront.product('camiseta-preta')
    end
    assert_equal [{ id: 'gid://shopify/Product/10790980190502' }, { handle: 'camiseta-preta' }], seen
  end
end
