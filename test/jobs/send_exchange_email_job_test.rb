require 'test_helper'

class SendExchangeEmailJobTest < ActiveSupport::TestCase
  def build_request(coupon_code: nil)
    client = Client.create!(
      name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com",
      email_sending_domain: 'loja.com.br', ses_verification_status: 'verified'
    )
    ExchangeConfig.create!(
      client: client,
      requested_email_subject: 'Recebemos sua solicitação',
      requested_email_body: 'Olá {{customer_name}}, recebemos o pedido {{order_number}}.',
      approved_email_subject: 'Troca aprovada',
      approved_email_body: 'Use o cupom {{coupon_code}} na sua próxima compra.'
    )
    ExchangeRequest.create!(
      client: client, shopify_order_id: '1', shopify_order_number: '#1001',
      customer_email: 'ana@example.com', customer_name: 'Ana', coupon_code: coupon_code
    )
  end

  test 'sends the requested e-mail with placeholders interpolated' do
    request = build_request
    fake_service = Minitest::Mock.new
    fake_service.expect(:call, true) do |args|
      args[:to] == 'ana@example.com' &&
        args[:subject] == 'Recebemos sua solicitação' &&
        args[:html_body] == 'Olá Ana, recebemos o pedido #1001.'
    end

    Ses::SendEmailService.stub :new, fake_service do
      SendExchangeEmailJob.perform_now(exchange_request_id: request.id, kind: 'requested')
    end

    fake_service.verify
  end

  test 'interpolates the coupon code on the approved e-mail' do
    request = build_request(coupon_code: 'RECABC12345')
    fake_service = Minitest::Mock.new
    fake_service.expect(:call, true) do |args|
      args[:html_body] == 'Use o cupom RECABC12345 na sua próxima compra.'
    end

    Ses::SendEmailService.stub :new, fake_service do
      SendExchangeEmailJob.perform_now(exchange_request_id: request.id, kind: 'approved')
    end

    fake_service.verify
  end

  test 'does nothing when the client has no ExchangeConfig' do
    client = Client.create!(name: 'Sem config', email: "sem-config-#{SecureRandom.hex(4)}@example.com")
    request = ExchangeRequest.create!(
      client: client, shopify_order_id: '1', shopify_order_number: '#1001', customer_email: 'ana@example.com'
    )

    assert_nothing_raised do
      SendExchangeEmailJob.perform_now(exchange_request_id: request.id, kind: 'requested')
    end
  end
end
