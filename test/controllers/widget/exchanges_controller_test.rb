require 'test_helper'

class Widget::ExchangesControllerTest < ActionDispatch::IntegrationTest
  def build_client
    Client.create!(
      name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com",
      shopify_shop_url: 'loja-teste.myshopify.com', shopify_access_token: 'token123'
    )
  end

  def build_config(client, active: true)
    ExchangeConfig.create!(client: client, active: active, company_name: 'Loja Teste')
  end

  class AlwaysAllowThrottle
    def allow?(_key) = true
  end

  def shopify_order(overrides = {})
    {
      id: '555001', number: '#1001', email: 'ana@example.com', cancelled: false,
      fulfilled_at: 2.days.ago,
      items: [{ sku: 'SKU-1', product_name: 'Camiseta', variant_title: 'P', quantity: 1, price: 99.9 }]
    }.merge(overrides)
  end

  test 'new renders the lookup form for an active config' do
    config = build_config(build_client)

    get new_troca_path(config.slug)

    assert_response :success
  end

  test 'new returns 404 for an unknown token' do
    get new_troca_path('does-not-exist')
    assert_response :not_found
  end

  test 'new returns 404 for an inactive config' do
    config = build_config(build_client, active: false)
    get new_troca_path(config.slug)
    assert_response :not_found
  end

  test 'lookup shows the order items when found' do
    config = build_config(build_client)

    Exchange::LookupThrottle.stub :new, AlwaysAllowThrottle.new do
      Shopify::FindOrderForExchange.stub :call, shopify_order do
        post lookup_troca_path(config.slug), params: { order_number: '1001', email: 'ana@example.com' }
      end
    end

    assert_response :success
    assert_match 'Camiseta', response.body
  end

  test 'lookup re-renders the form with an error when the order is not found' do
    config = build_config(build_client)

    Exchange::LookupThrottle.stub :new, AlwaysAllowThrottle.new do
      Shopify::FindOrderForExchange.stub :call, nil do
        post lookup_troca_path(config.slug), params: { order_number: '9999', email: 'ana@example.com' }
      end
    end

    assert_response :unprocessable_entity
  end

  test 'create persists the request with only the eligible kind and enqueues the requested e-mail and Zapi notification' do
    config = build_config(build_client)

    assert_enqueued_with(job: SendExchangeEmailJob) do
      assert_enqueued_with(job: NotifyExchangeRequestJob) do
        Exchange::LookupThrottle.stub :new, AlwaysAllowThrottle.new do
          Shopify::FindOrderForExchange.stub :call, shopify_order do
            post troca_path(config.slug), params: {
              order_number: '1001', email: 'ana@example.com', customer_name: 'Ana',
              items: [{ sku: 'SKU-1', kind: 'troca', reason: 'tamanho_nao_serviu' }]
            }
          end
        end
      end
    end

    assert_response :success
    request = ExchangeRequest.last
    assert_equal 'ana@example.com', request.customer_email
    assert_equal 1, request.exchange_request_items.count
    assert_equal 'Camiseta', request.exchange_request_items.first.product_name
  end

  test 'create ignores a devolucao selection when the order is past the return window' do
    config = build_config(build_client)
    old_order = shopify_order(fulfilled_at: 30.days.ago)

    Exchange::LookupThrottle.stub :new, AlwaysAllowThrottle.new do
      Shopify::FindOrderForExchange.stub :call, old_order do
        post troca_path(config.slug), params: {
          order_number: '1001', email: 'ana@example.com',
          items: [{ sku: 'SKU-1', kind: 'devolucao', reason: 'nao_gostei' }]
        }
      end
    end

    assert_response :unprocessable_entity
    assert_equal 0, ExchangeRequest.count
  end

  test 'create shows a friendly error and persists nothing when defeito reason has no photo' do
    config = build_config(build_client)

    Exchange::LookupThrottle.stub :new, AlwaysAllowThrottle.new do
      Shopify::FindOrderForExchange.stub :call, shopify_order do
        post troca_path(config.slug), params: {
          order_number: '1001', email: 'ana@example.com',
          items: [{ sku: 'SKU-1', kind: 'troca', reason: ExchangeRequestItem::DEFECT_REASON }]
        }
      end
    end

    assert_response :unprocessable_entity
    assert_equal 0, ExchangeRequest.count
    assert_equal 0, ExchangeRequestItem.count
  end
end
