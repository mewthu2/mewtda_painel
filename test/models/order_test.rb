require 'test_helper'

class OrderTest < ActiveSupport::TestCase
  def build_client
    Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
  end

  test 'stores subtotal_price, total_discounts, total_price and cancelled_at' do
    client = build_client

    order = Order.create!(
      client: client,
      shopify_order_id: '1001',
      subtotal_price: 100.0,
      total_discounts: 10.0,
      total_price: 90.0,
      cancelled_at: nil
    )

    assert_equal 100.0, order.subtotal_price.to_f
    assert_equal 10.0, order.total_discounts.to_f
    assert_equal 90.0, order.total_price.to_f
    assert_nil order.cancelled_at
  end

  test 'not_cancelled scope excludes orders with cancelled_at set' do
    client = build_client

    active = Order.create!(client: client, shopify_order_id: '2001', cancelled_at: nil)
    cancelled = Order.create!(client: client, shopify_order_id: '2002', cancelled_at: Time.current)

    result = Order.not_cancelled

    assert_includes result, active
    assert_not_includes result, cancelled
  end
end
