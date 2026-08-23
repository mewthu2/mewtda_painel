require 'test_helper'

class AffiliatesControllerTest < ActionDispatch::IntegrationTest
  def build_user(admin: false, client: nil)
    profile_id = admin ? Profile::ADMIN : Profile::USER
    Profile.find_or_create_by!(id: profile_id) { |p| p.name = admin ? 'Admin' : 'User' }

    User.create!(
      name: 'User', email: "user-#{SecureRandom.hex(4)}@example.com",
      password: 'password123', password_confirmation: 'password123',
      profile_id: profile_id, client: client
    )
  end

  test 'redirects when the admin has no client selected' do
    admin = build_user(admin: true)
    sign_in admin

    get affiliates_path

    assert_redirected_to crm_path
  end

  test 'allows an admin via the selected client in session' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    admin = build_user(admin: true)
    sign_in admin

    post update_selected_client_path, params: { client_id: client.id }
    get affiliates_path

    assert_response :success
  end

  test 'allows a non-admin client user' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    user = build_user(client: client)
    sign_in user

    get affiliates_path

    assert_response :success
  end

  test 'index aggregates real order sales per affiliate coupon' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    Profile.find_or_create_by!(id: Profile::AFFILIATE) { |p| p.name = 'Afiliado' }
    affiliate = User.create!(
      name: 'Joao', email: "joao-#{SecureRandom.hex(4)}@example.com",
      password: 'password123', password_confirmation: 'password123',
      profile_id: Profile::AFFILIATE, client: client, utm_code: 'joao123', discount_code: 'JOAO10'
    )
    unused_affiliate = User.create!(
      name: 'Maria', email: "maria-#{SecureRandom.hex(4)}@example.com",
      password: 'password123', password_confirmation: 'password123',
      profile_id: Profile::AFFILIATE, client: client, utm_code: 'maria456', discount_code: 'MARIA10'
    )

    Order.create!(client: client, shopify_order_id: SecureRandom.hex(6), shopify_creation_date: Time.current,
                  subtotal_price: 100, total_discounts: 10, total_price: 90, total_shipping_price: 10,
                  discount_code: 'JOAO10')
    Order.create!(client: client, shopify_order_id: SecureRandom.hex(6), shopify_creation_date: Time.current,
                  subtotal_price: 200, total_discounts: 20, total_price: 180, total_shipping_price: 0,
                  discount_code: 'JOAO10')
    # pedido cancelado com o mesmo cupom -- nao deve contar
    Order.create!(client: client, shopify_order_id: SecureRandom.hex(6), shopify_creation_date: Time.current,
                  subtotal_price: 999, total_discounts: 0, total_price: 999, total_shipping_price: 0,
                  discount_code: 'JOAO10', cancelled_at: Time.current)

    user = build_user(client: client)
    sign_in user

    get affiliates_path

    assert_response :success
    assert_match 'R$ 310,00', response.body # 100 + 10 + 200 = 310, sem o cancelado
    assert_match affiliate.discount_code, response.body
    assert_match unused_affiliate.discount_code, response.body
  end

  test 'shows a warning when site_url is not configured' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    user = build_user(client: client)
    sign_in user

    get affiliates_path

    assert_match 'Site principal não configurado', response.body
  end

  test 'update_settings saves the site_url' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    user = build_user(client: client)
    sign_in user

    patch settings_affiliates_path, params: { client: { site_url: 'https://sualojaexemplo.com.br' } }

    assert_redirected_to affiliates_path
    assert_equal 'https://sualojaexemplo.com.br', client.reload.site_url
  end

  test 'update_settings rejects a URL without scheme' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    user = build_user(client: client)
    sign_in user

    patch settings_affiliates_path, params: { client: { site_url: 'sualojaexemplo.com.br' } }

    assert_response :unprocessable_entity
    assert_nil client.reload.site_url
  end
end
