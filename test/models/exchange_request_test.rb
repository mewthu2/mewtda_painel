require 'test_helper'

class ExchangeRequestTest < ActiveSupport::TestCase
  def build_client
    Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
  end

  def build_request(overrides = {})
    ExchangeRequest.create!({
      client: build_client, shopify_order_id: '1', shopify_order_number: '#1001',
      customer_email: 'ana@example.com'
    }.merge(overrides))
  end

  test 'defaults to pending status' do
    assert build_request.pending?
  end

  test 'requires shopify_order_id, shopify_order_number and customer_email' do
    request = ExchangeRequest.new(client: build_client)
    assert_not request.valid?
    assert_includes request.errors.attribute_names, :shopify_order_id
    assert_includes request.errors.attribute_names, :shopify_order_number
    assert_includes request.errors.attribute_names, :customer_email
  end

  test 'troca_total sums only troca items' do
    request = build_request
    request.exchange_request_items.create!(product_name: 'A', quantity: 2, price: 50, kind: :troca, reason: 'outro')
    request.exchange_request_items.create!(product_name: 'B', quantity: 1, price: 30, kind: :devolucao, reason: 'outro')

    assert_equal 100.0, request.troca_total
  end

  test 'troca_total is zero without any troca item' do
    request = build_request
    request.exchange_request_items.create!(product_name: 'B', quantity: 1, price: 30, kind: :devolucao, reason: 'outro')

    assert_equal 0.0, request.troca_total
  end

  test 'destroying a request destroys its items' do
    request = build_request
    item = request.exchange_request_items.create!(product_name: 'A', quantity: 1, price: 10, kind: :troca, reason: 'outro')

    request.destroy

    assert_not ExchangeRequestItem.exists?(item.id)
  end

  test 'a client has many exchange_requests, destroyed with it' do
    client = build_client
    request = build_request(client: client)

    client.destroy

    assert_not ExchangeRequest.exists?(request.id)
  end
end
