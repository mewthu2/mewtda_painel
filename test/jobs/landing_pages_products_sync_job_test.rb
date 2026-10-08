require 'test_helper'

class LandingPagesProductsSyncJobTest < ActiveJob::TestCase
  test 'syncs active pages of clients with a storefront token' do
    shop = Client.create!(name: 'HENRRI', email: "a-#{SecureRandom.hex(4)}@example.com",
                          shopify_shop_url: 'henrri.myshopify.com', shopify_storefront_token: 'token')
    no_token = Client.create!(name: 'Outra', email: "b-#{SecureRandom.hex(4)}@example.com")
    live = shop.landing_pages.create!(name: 'No ar', slug: 'no-ar', template: 'drop_01_1822', active: true)
    shop.landing_pages.create!(name: 'Rascunho', slug: 'rascunho', template: 'drop_01_1822', active: false)
    no_token.landing_pages.create!(name: 'Sem token', slug: 'sem-token', template: 'drop_01_1822', active: true)

    synced = []
    fake_new = ->(page) { Struct.new(:page) { def call = LandingPages::SyncProducts::Result.new(ok: true) }.new(page).tap { synced << page.id } }
    LandingPages::SyncProducts.stub :new, fake_new do
      LandingPagesProductsSyncJob.perform_now
    end

    assert_equal [live.id], synced
  end

  test 'is scheduled daily' do
    schedule = YAML.load_file(Rails.root.join('config/schedule.yml'))
    assert_equal 'LandingPagesProductsSyncJob', schedule.dig('landing_pages_products_sync', 'class')
  end
end
