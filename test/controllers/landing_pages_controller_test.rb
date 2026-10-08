require 'test_helper'

class LandingPagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @client = Client.create!(name: 'HENRRI', email: "loja-#{SecureRandom.hex(4)}@example.com")
    Profile.find_or_create_by!(id: Profile::USER) { |p| p.name = 'User' }
    @user = User.create!(name: 'U', email: "u-#{SecureRandom.hex(4)}@example.com", password: 'password123',
                         password_confirmation: 'password123', profile_id: Profile::USER, client: @client)
    sign_in @user
  end

  test 'creates a landing page for the current client' do
    post landing_pages_path, params: { landing_page: {
      name: '1822 · Drop 01', path_prefix: 'use1822', slug: 'drop-01', template: 'drop_01_1822',
      active: '1', product_handles_text: "camiseta-ladrao-branca\ncamiseta-ladrao-preta"
    } }

    page = @client.landing_pages.last
    assert_redirected_to landing_page_path(page)
    assert_equal '/use1822/drop-01', page.public_path
    assert_equal %w[camiseta-ladrao-branca camiseta-ladrao-preta], page.product_handles
  end

  test 'index and show render with stats' do
    page = @client.landing_pages.create!(name: 'Drop', slug: 'drop-01', template: 'drop_01_1822')
    page.leads.create!(name: 'Ana', email: 'ana@example.com', status: 'success', existing_customer: true)

    get landing_pages_path
    assert_response :success
    assert_match '/henrri/drop-01', response.body

    get landing_page_path(page)
    assert_response :success
    assert_match 'ana@example.com', response.body
    assert_match 'Já era cliente', response.body
  end

  test 'sync button refreshes the stored products and shows when it ran' do
    page = @client.landing_pages.create!(name: 'Drop', slug: 'drop-01', template: 'drop_01_1822')
    result = LandingPages::SyncProducts::Result.new(ok: true, products_count: 3)
    synced = []
    fake_new = lambda do |landing_page|
      Object.new.tap { |o| o.define_singleton_method(:call) { synced << landing_page.id; landing_page.update_columns(storefront_synced_at: Time.zone.local(2026, 10, 8, 9, 30)); result } }
    end

    LandingPages::SyncProducts.stub :new, fake_new do
      post sync_products_landing_page_path(page)
    end

    assert_equal [page.id], synced
    assert_redirected_to landing_page_path(page)
    follow_redirect!
    assert_match 'Produtos sincronizados com a Shopify (3).', response.body
    assert_match 'sincronizados com a Shopify em 08/10 às 09:30', response.body
  end

  test 'sync button shows the error when the Shopify fails' do
    page = @client.landing_pages.create!(name: 'Drop', slug: 'drop-01', template: 'drop_01_1822')
    result = LandingPages::SyncProducts::Result.new(ok: false, error: 'A Shopify não respondeu (HTTP 503).')

    LandingPages::SyncProducts.stub :new, ->(_) { Struct.new(:r) { def call = r }.new(result) } do
      post sync_products_landing_page_path(page)
    end

    follow_redirect!
    assert_match 'A Shopify não respondeu (HTTP 503).', response.body
  end

  test 'cannot see another client landing page' do
    other = Client.create!(name: 'Outra', email: 'o@example.com').landing_pages
                  .create!(name: 'X', slug: 'x', template: 'drop_01_1822')

    get landing_page_path(other)
    assert_response :not_found
  end

  test 'saving settings keeps the storefront token when left blank' do
    @client.update!(shopify_storefront_token: 'sf-token')

    patch settings_path, params: { client: { name: 'HENRRI', shopify_storefront_token: '' } }

    assert_equal 'sf-token', @client.reload.shopify_storefront_token
  end

  test 'the settings page shows the Storefront API token field' do
    get edit_settings_path

    assert_response :success
    assert_match 'Token da Storefront API', response.body
    assert_match 'client[shopify_storefront_token]', response.body
  end
end
