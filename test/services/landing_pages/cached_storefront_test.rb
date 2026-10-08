require 'test_helper'

class LandingPages::CachedStorefrontTest < ActiveSupport::TestCase
  setup do
    @client = Client.create!(name: 'HENRRI', email: "loja-#{SecureRandom.hex(4)}@example.com")
    @page = @client.landing_pages.create!(name: 'Drop', slug: 'drop-01', template: 'drop_01_1822')
    @calls = []
    calls = @calls
    @live = Object.new
    @live.define_singleton_method(:product) { |ref| calls << ref; ref == 'sumiu' ? nil : { 'id' => ref, 'title' => "Produto #{ref}" } }
    @live.define_singleton_method(:kit_prices) { |id, max: 4| calls << id; (1..max).to_h { |q| [q, (69.9 * q).to_d] } }
  end

  test 'fetches a missing product once and keeps it on the page' do
    assert_equal 'Produto a', LandingPages::CachedStorefront.new(@page, @live).product('a')['title']

    again = LandingPages::CachedStorefront.new(@page.reload, @live)
    assert_equal 'Produto a', again.product('a')['title']
    assert_equal ['a'], @calls
    assert_equal 'Produto a', @page.reload.storefront_cache.dig('products', 'a', 'title')
  end

  test 'does not store products the store does not return' do
    cache = LandingPages::CachedStorefront.new(@page, @live)
    assert_nil cache.product('sumiu')
    assert_nil cache.product('sumiu')
    assert_equal %w[sumiu sumiu], @calls
    assert_equal({}, @page.reload.storefront_cache)
  end

  test 'adding a product keeps what another visit stored meanwhile' do
    LandingPages::CachedStorefront.new(LandingPage.find(@page.id), @live).product('a')
    LandingPages::CachedStorefront.new(@page, @live).product('b') # @page ainda sem o "a" em memória

    assert_equal %w[a b], @page.reload.storefront_cache['products'].keys.sort
  end

  test 'stores kit prices as decimals and refetches when more quantities are asked' do
    cache = LandingPages::CachedStorefront.new(@page, @live)
    assert_equal({ 1 => 69.9.to_d, 2 => 139.8.to_d }, cache.kit_prices('v1', max: 2))
    assert_equal({ 1 => 69.9.to_d, 2 => 139.8.to_d }, LandingPages::CachedStorefront.new(@page.reload, @live).kit_prices('v1', max: 2))
    assert_equal 4, LandingPages::CachedStorefront.new(@page.reload, @live).kit_prices('v1', max: 4).size
    assert_equal %w[v1 v1], @calls
  end
end
