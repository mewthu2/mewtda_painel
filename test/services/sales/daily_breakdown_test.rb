require 'test_helper'

class Sales::DailyBreakdownTest < ActiveSupport::TestCase
  def setup
    @client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
  end

  def create_order(attrs = {})
    Order.create!({
      client: @client,
      shopify_order_id: SecureRandom.hex(6),
      shopify_creation_date: Time.zone.local(2026, 3, 15),
      subtotal_price: 100,
      total_discounts: 0,
      total_price: 100,
      cancelled_at: nil
    }.merge(attrs))
  end

  def call(client: @client, year: 2026, month: 3)
    Sales::DailyBreakdown.new(client: client, year: year, month: month).call
  end

  test 'groups revenue, orders and avg ticket by day for a past month' do
    create_order(shopify_creation_date: Time.zone.local(2026, 3, 1), total_price: 100)
    create_order(shopify_creation_date: Time.zone.local(2026, 3, 1), total_price: 50)
    create_order(shopify_creation_date: Time.zone.local(2026, 3, 3), total_price: 300)
    create_order(shopify_creation_date: Time.zone.local(2026, 2, 28), total_price: 999) # outside the month

    result = call

    assert_equal 31, result[:days].length
    assert_equal 150.0, result[:revenue_by_day][0].to_f
    assert_equal 2, result[:orders_by_day][0]
    assert_equal 75.0, result[:avg_ticket_by_day][0].to_f
    assert_equal 0.0, result[:revenue_by_day][1].to_f
    assert_nil result[:avg_ticket_by_day][1]
    assert_equal 300.0, result[:revenue_by_day][2].to_f
  end

  test 'excludes cancelled orders' do
    create_order(total_price: 100)
    create_order(total_price: 500, cancelled_at: Time.current)

    result = call

    assert_equal 100.0, result[:revenue_total].to_f
    assert_equal 1, result[:orders_total]
  end

  test 'totals and has_data reflect the whole month' do
    create_order(shopify_creation_date: Time.zone.local(2026, 3, 1), total_price: 100)
    create_order(shopify_creation_date: Time.zone.local(2026, 3, 20), total_price: 300)

    result = call

    assert_equal 400.0, result[:revenue_total].to_f
    assert_equal 2, result[:orders_total]
    assert_equal 200.0, result[:avg_ticket_total].to_f
    assert result[:has_data]
  end

  test 'has_data is false and totals are zero/nil when the client has no orders in the month' do
    result = call

    assert_not result[:has_data]
    assert_equal 0.0, result[:revenue_total].to_f
    assert_equal 0, result[:orders_total]
    assert_nil result[:avg_ticket_total]
    assert result[:revenue_by_day].all? { |v| v.to_f == 0.0 }
    assert result[:orders_by_day].all?(&:zero?)
  end

  test 'buckets a late-night order by its local (Brasília) day, not by the UTC-stored date' do
    # 23:39 em Brasília (-03:00) é gravado no banco como "2026-03-16 02:39"
    # (UTC-equivalente, sem timezone). Sem o ajuste de -3h, DATE() na consulta
    # SQL trunca usando esse valor bruto e o pedido "vaza" pro dia 16.
    create_order(shopify_creation_date: Time.zone.local(2026, 3, 15, 23, 39), total_price: 100)

    result = call

    assert_equal 100.0, result[:revenue_by_day][14].to_f # índice 14 = dia 15
    assert_equal 1, result[:orders_by_day][14]
    assert_equal 0.0, result[:revenue_by_day][15].to_f # dia 16 deve ficar vazio
    assert_equal 0, result[:orders_by_day][15]
  end

  test 'caps days at today when the requested month is the current month' do
    travel_to Time.zone.local(2026, 3, 10) do
      create_order(shopify_creation_date: Time.zone.local(2026, 3, 5), total_price: 100)

      result = call

      assert_equal 10, result[:days].length
      assert_equal 10, result[:days].last
    end
  end
end
