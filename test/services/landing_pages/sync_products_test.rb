require 'test_helper'

class LandingPages::SyncProductsTest < ActiveSupport::TestCase
  FakeStorefront = Struct.new(:products, :failing) do
    def configured? = true

    def fetch_product!(ref)
      raise Shopify::Storefront::Error, 'HTTP 503' if failing
      products[ref]
    end

    def fetch_kit_prices!(variant_id, max: 4)
      (1..max).to_h { |q| [q, (60 * q).to_d] } unless variant_id == 'v-sem-cotacao'
    end
  end

  def product(id, title, variants: ["v#{id}"])
    { 'id' => id, 'title' => title, 'variants' => { 'nodes' => variants.map { |v| { 'id' => v } } } }
  end

  setup do
    @client = Client.create!(name: 'HENRRI', email: "loja-#{SecureRandom.hex(4)}@example.com")
    @page = @client.landing_pages.create!(name: 'Drop', slug: 'drop-01', template: 'drop_01_1822', product_handles: %w[a])
    @page.update_columns(storefront_cache: {
      'products' => { 'a' => product('a', 'Velho'), 'extra' => product('extra', 'Extra'), 'apagado' => product('apagado', 'Apagado') },
      'kit_prices' => { 'va' => { '1' => '69.9', '2' => '130' }, 'vapagado' => { '1' => '1' } }
    })
  end

  test 'refreshes handles and stored products, drops what left the store' do
    store = FakeStorefront.new({ 'a' => product('a', 'Novo'), 'extra' => product('extra', 'Extra 2') }, false)

    result = travel_to(Time.zone.local(2026, 10, 8, 5)) { LandingPages::SyncProducts.new(@page, store).call }

    assert result.ok
    assert_equal 2, result.products_count
    @page.reload
    assert_equal({ 'a' => 'Novo', 'extra' => 'Extra 2' }, @page.storefront_cache['products'].transform_values { |p| p['title'] })
    assert_equal({ 'va' => { '1' => '60.0', '2' => '120.0' } }, @page.storefront_cache['kit_prices'])
    assert_equal Time.zone.local(2026, 10, 8, 5), @page.storefront_synced_at
  end

  test 'keeps everything when the Shopify fails' do
    before = @page.storefront_cache

    result = LandingPages::SyncProducts.new(@page, FakeStorefront.new({}, true)).call

    assert_not result.ok
    assert_match 'HTTP 503', result.error
    assert_equal before, @page.reload.storefront_cache
    assert_nil @page.storefront_synced_at
  end

  test 'fails without a storefront token' do
    result = LandingPages::SyncProducts.new(@page).call
    assert_not result.ok
    assert_match 'Token da Storefront', result.error
  end
end
