require 'test_helper'

class Shopify::OrdersTest < ActiveSupport::TestCase
  setup do
    # Shopify::Orders memoizes @location as a class-level ivar across calls (pre-existing
    # behavior, out of scope for this task). Reset it so each test resolves its own
    # Location instead of reusing one from a previous test's rolled-back transaction.
    Shopify::Orders.instance_variable_set(:@location, nil)
  end

  def build_client
    Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
  end

  def shopify_order_payload(overrides = {})
    {
      'id' => 555_001,
      'name' => '#1001',
      'created_at' => '2026-03-10T12:00:00-03:00',
      'tags' => 'VendedoraElo, promo',
      'subtotal_price' => '200.00',
      'total_discounts' => '20.00',
      'total_price' => '180.00',
      'cancelled_at' => nil,
      'note_attributes' => [],
      'line_items' => [],
      'customer' => nil
    }.merge(overrides)
  end

  test 'persists tags, subtotal_price, total_discounts, total_price and cancelled_at' do
    client = build_client

    order = Shopify::Orders.create_or_update_order_from_shopify(
      shopify_order_payload,
      session: nil,
      client: client
    )

    order.reload
    assert_equal 'VendedoraElo, promo', order.tags
    assert_equal 200.00, order.subtotal_price.to_f
    assert_equal 20.00, order.total_discounts.to_f
    assert_equal 180.00, order.total_price.to_f
    assert_nil order.cancelled_at
  end

  test 'persists cancelled_at when the Shopify order was cancelled' do
    client = build_client

    order = Shopify::Orders.create_or_update_order_from_shopify(
      shopify_order_payload('id' => 555_002, 'cancelled_at' => '2026-03-11T09:00:00-03:00'),
      session: nil,
      client: client
    )

    assert order.reload.cancelled_at.present?
  end

  test 'attributes the order to the landing page from the _landing_page note attribute' do
    client = build_client
    landing_page = client.landing_pages.create!(name: 'Drop', slug: 'drop-01', template: 'drop_01_1822')

    order = Shopify::Orders.create_or_update_order_from_shopify(
      shopify_order_payload('id' => 555_003,
                            'note_attributes' => [{ 'name' => '_landing_page', 'value' => landing_page.id.to_s }]),
      session: nil,
      client: client
    )

    assert_equal landing_page.id, order.reload.landing_page_id
  end

  test 'ignores a _landing_page attribute that belongs to another client' do
    client = build_client
    other_page = build_client.landing_pages.create!(name: 'Outra', slug: 'outra', template: 'drop_01_1822')

    order = Shopify::Orders.create_or_update_order_from_shopify(
      shopify_order_payload('id' => 555_004,
                            'note_attributes' => [{ 'name' => '_landing_page', 'value' => other_page.id.to_s }]),
      session: nil,
      client: client
    )

    assert_nil order.reload.landing_page_id
  end
end
