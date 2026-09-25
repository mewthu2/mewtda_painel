require 'test_helper'

class ExchangeRequestsControllerTest < ActionDispatch::IntegrationTest
  def build_client
    Client.create!(
      name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com",
      shopify_shop_url: 'loja-teste.myshopify.com', shopify_access_token: 'token123'
    )
  end

  def build_user(client:)
    Profile.find_or_create_by!(id: Profile::USER) { |p| p.name = 'User' }
    User.create!(
      name: 'User', email: "user-#{SecureRandom.hex(4)}@example.com",
      password: 'password123', password_confirmation: 'password123', profile_id: Profile::USER, client: client
    )
  end

  def build_request(client)
    ExchangeConfig.create!(client: client, coupon_validity_days: 30)
    ExchangeRequest.create!(
      client: client, shopify_order_id: '1', shopify_order_number: '#1001', customer_email: 'ana@example.com'
    )
  end

  test 'index lists the client requests' do
    client = build_client
    build_request(client)
    sign_in build_user(client: client)

    get exchange_requests_path

    assert_response :success
    assert_match '#1001', response.body
  end

  test 'show displays the request items' do
    client = build_client
    request = build_request(client)
    request.exchange_request_items.create!(product_name: 'Camiseta', quantity: 1, price: 50, kind: :troca, reason: 'outro')
    sign_in build_user(client: client)

    get exchange_request_path(request)

    assert_response :success
    assert_match 'Camiseta', response.body
  end

  test 'update with status approved calls Exchange::Approve and enqueues the e-mail' do
    client = build_client
    request = build_request(client)
    request.exchange_request_items.create!(product_name: 'Camiseta', quantity: 1, price: 50, kind: :troca, reason: 'outro')
    sign_in build_user(client: client)

    Shopify::CreateDiscountCode.stub :call, 'RECABC12345' do
      assert_enqueued_with(job: SendExchangeEmailJob, args: [{ exchange_request_id: request.id, kind: 'approved' }]) do
        patch exchange_request_path(request), params: { status: 'approved' }
      end
    end

    assert request.reload.approved?
    assert_equal 'RECABC12345', request.coupon_code
  end

  test 'update with status rejected enqueues the rejected e-mail' do
    client = build_client
    request = build_request(client)
    sign_in build_user(client: client)

    assert_enqueued_with(job: SendExchangeEmailJob, args: [{ exchange_request_id: request.id, kind: 'rejected' }]) do
      patch exchange_request_path(request), params: { status: 'rejected' }
    end

    assert request.reload.rejected?
  end

  test 'update with status completed enqueues the completed e-mail' do
    client = build_client
    request = build_request(client)
    request.update!(status: :approved)
    sign_in build_user(client: client)

    assert_enqueued_with(job: SendExchangeEmailJob, args: [{ exchange_request_id: request.id, kind: 'completed' }]) do
      patch exchange_request_path(request), params: { status: 'completed' }
    end

    assert request.reload.completed?
  end
end
