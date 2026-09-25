require 'test_helper'

class Exchange::ApproveTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def build_request
    client = Client.create!(
      name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com",
      shopify_shop_url: 'loja-teste.myshopify.com', shopify_access_token: 'token123'
    )
    ExchangeConfig.create!(client: client, coupon_validity_days: 15)
    ExchangeRequest.create!(
      client: client, shopify_order_id: '1', shopify_order_number: '#1001', customer_email: 'ana@example.com'
    )
  end

  test 'approves and generates a coupon for the troca items total' do
    request = build_request
    request.exchange_request_items.create!(product_name: 'A', quantity: 2, price: 50, kind: :troca, reason: 'outro')
    request.exchange_request_items.create!(product_name: 'B', quantity: 1, price: 30, kind: :devolucao, reason: 'outro')

    captured = nil
    Shopify::CreateDiscountCode.stub :call, ->(**kwargs) { captured = kwargs; 'RECABC12345' } do
      Exchange::Approve.new(request).call
    end

    request.reload
    assert request.approved?
    assert_equal 'RECABC12345', request.coupon_code
    assert_equal 100.0, captured[:amount]
    assert_equal 15.days, captured[:expires_in]
  end

  test 'approves without generating a coupon when there is no troca item' do
    request = build_request
    request.exchange_request_items.create!(product_name: 'B', quantity: 1, price: 30, kind: :devolucao, reason: 'outro')

    Shopify::CreateDiscountCode.stub :call, ->(**) { raise 'should not be called' } do
      Exchange::Approve.new(request).call
    end

    request.reload
    assert request.approved?
    assert_nil request.coupon_code
  end

  test 'enqueues the approved e-mail job' do
    request = build_request

    assert_enqueued_with(job: SendExchangeEmailJob, args: [{ exchange_request_id: request.id, kind: 'approved' }]) do
      Exchange::Approve.new(request).call
    end
  end
end
