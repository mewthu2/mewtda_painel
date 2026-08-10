require 'test_helper'

class Sales::MonthlyMetricsTest < ActiveSupport::TestCase
  def setup
    @client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
    @integration_user = IntegrationUser.create!(
      name: 'Pixel', slug: "pixel-#{SecureRandom.hex(4)}", api_secret: SecureRandom.hex(8), client: @client
    )
  end

  def create_order(attrs = {})
    Order.create!({
      client: @client,
      shopify_order_id: SecureRandom.hex(6),
      shopify_creation_date: Time.zone.local(2026, 3, 15),
      subtotal_price: 100,
      total_discounts: 0,
      total_price: 100,
      cancelled_at: nil,
      tags: nil
    }.merge(attrs))
  end

  def create_page_view(session_id, at: Time.zone.local(2026, 3, 15))
    ShopifyEvent.create!(
      client: @client, integration_user: @integration_user, kind: 'page_viewed',
      session_id: session_id, created_at: at
    )
  end

  def call(tag: nil)
    Sales::MonthlyMetrics.new(client: @client, year: 2026, month: 3, tag: tag).call
  end

  test 'revenue, gross_sales and discounts sum total_price/subtotal_price/total_discounts of the month' do
    create_order(total_price: 100, subtotal_price: 120, total_discounts: 20)
    create_order(total_price: 50, subtotal_price: 50, total_discounts: 0)
    create_order(shopify_creation_date: Time.zone.local(2026, 2, 15), total_price: 999) # outside the month

    result = call

    assert_equal 150.0, result[:revenue].to_f
    assert_equal 170.0, result[:gross_sales].to_f
    assert_equal 20.0, result[:discounts].to_f
    assert_equal 2, result[:orders_count]
  end

  test 'excludes cancelled orders' do
    create_order(total_price: 100)
    create_order(total_price: 500, cancelled_at: Time.current)

    result = call

    assert_equal 100.0, result[:revenue].to_f
    assert_equal 1, result[:orders_count]
  end

  test 'avg_ticket is revenue divided by orders_count, nil when there are no orders' do
    create_order(total_price: 100)
    create_order(total_price: 300)

    assert_equal 200.0, call[:avg_ticket].to_f

    empty_client = Client.create!(name: 'Vazia', email: "vazia-#{SecureRandom.hex(4)}@example.com")
    result = Sales::MonthlyMetrics.new(client: empty_client, year: 2026, month: 3).call
    assert_nil result[:avg_ticket]
  end

  test 'tag filter restricts the order scope without affecting session count' do
    create_order(total_price: 100, tags: 'VendedoraElo, promo')
    create_order(total_price: 300, tags: 'outra-tag')
    create_page_view('s1')
    create_page_view('s2')

    result = call(tag: 'VendedoraElo')

    assert_equal 100.0, result[:revenue].to_f
    assert_equal 1, result[:orders_count]
    assert_equal 50.0, result[:conversion_rate]
  end

  test 'conversion_rate is orders_count / unique sessions * 100, nil when there are no sessions' do
    create_order
    create_order
    create_page_view('s1')
    create_page_view('s1') # same session, counted once
    create_page_view('s2')
    create_page_view('s2')

    assert_equal 100.0, call[:conversion_rate]

    empty_client = Client.create!(name: 'Vazia', email: "vazia2-#{SecureRandom.hex(4)}@example.com")
    result = Sales::MonthlyMetrics.new(client: empty_client, year: 2026, month: 3).call
    assert_nil result[:conversion_rate]
  end

  test 'ad_cost_available is false and roas/cac are nil when a configured platform has no snapshot yet' do
    @client.update!(meta_access_token: 'token', meta_ad_account_id: 'act_1')
    create_order(total_price: 100)

    result = call

    assert_equal ['meta'], result[:configured_platforms]
    assert_not result[:ad_cost_available]
    assert_nil result[:roas]
    assert_nil result[:cac]
  end

  test 'roas is revenue / ad_cost and cac is ad_cost / new_customers_count when costs are synced' do
    @client.update!(meta_access_token: 'token', meta_ad_account_id: 'act_1')
    AdCostSnapshot.create!(client: @client, platform: 'meta', year: 2026, month: 3, cost: 100, fetched_at: Time.current)

    new_customer = Customer.create!(shopify_customer_id: SecureRandom.hex(6))
    create_order(total_price: 400, customer: new_customer)

    result = call

    assert result[:ad_cost_available]
    assert_equal 100.0, result[:ad_cost].to_f
    assert_equal 4.0, result[:roas].to_f
    assert_equal 1, result[:new_customers_count]
    assert_equal 100.0, result[:cac].to_f
  end

  test 'ad_cost only counts snapshots for currently configured platforms' do
    @client.update!(meta_access_token: 'token', meta_ad_account_id: 'act_1')
    AdCostSnapshot.create!(client: @client, platform: 'meta', year: 2026, month: 3, cost: 100, fetched_at: Time.current)
    AdCostSnapshot.create!(client: @client, platform: 'google_ads', year: 2026, month: 3, cost: 900, fetched_at: Time.current)

    result = call

    assert_equal ['meta'], result[:configured_platforms]
    assert_equal 100.0, result[:ad_cost].to_f
  end

  test 'new_customers_count only counts customers whose earliest non-cancelled order falls in the month' do
    returning_customer = Customer.create!(shopify_customer_id: SecureRandom.hex(6))
    create_order(shopify_creation_date: Time.zone.local(2026, 1, 5), customer: returning_customer)
    create_order(shopify_creation_date: Time.zone.local(2026, 3, 10), customer: returning_customer)

    brand_new_customer = Customer.create!(shopify_customer_id: SecureRandom.hex(6))
    create_order(shopify_creation_date: Time.zone.local(2026, 3, 12), customer: brand_new_customer)

    assert_equal 1, call[:new_customers_count]
  end
end
