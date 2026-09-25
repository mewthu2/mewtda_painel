require 'test_helper'

class NotifyExchangeRequestJobTest < ActiveSupport::TestCase
  def build_request
    client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
    request = ExchangeRequest.create!(
      client: client, shopify_order_id: '1', shopify_order_number: '#1001',
      customer_email: 'ana@example.com', customer_name: 'Ana'
    )
    request.exchange_request_items.create!(product_name: 'Camiseta', quantity: 1, price: 50, kind: :troca, reason: 'outro')
    request
  end

  def with_notification_phone(value)
    original = ENV['ZAPI_NOTIFICATION_PHONE']
    ENV['ZAPI_NOTIFICATION_PHONE'] = value
    yield
  ensure
    ENV['ZAPI_NOTIFICATION_PHONE'] = original
  end

  test 'sends a WhatsApp message via the global (client-less) Zapi instance' do
    request = build_request
    captured_client = :not_called
    fake = Minitest::Mock.new
    fake.expect(:send_text, true) do |args|
      args[:phone] == '5511999998888' && args[:message].include?('Loja Teste') && args[:message].include?('#1001')
    end

    with_notification_phone('11999998888') do
      Zapi::Client.stub :new, ->(client) { captured_client = client; fake } do
        NotifyExchangeRequestJob.perform_now(exchange_request_id: request.id)
      end
    end

    assert_nil captured_client
    fake.verify
  end

  test 'does nothing when ZAPI_NOTIFICATION_PHONE is not set' do
    request = build_request

    with_notification_phone(nil) do
      Zapi::Client.stub :new, ->(*) { raise 'should not be called' } do
        assert_nothing_raised do
          NotifyExchangeRequestJob.perform_now(exchange_request_id: request.id)
        end
      end
    end
  end
end
