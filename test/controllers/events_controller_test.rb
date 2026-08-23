require 'test_helper'

class EventsControllerTest < ActionDispatch::IntegrationTest
  def build_user(admin: false, client: nil)
    profile_id = admin ? Profile::ADMIN : Profile::USER
    Profile.find_or_create_by!(id: profile_id) { |p| p.name = admin ? 'Admin' : 'User' }

    User.create!(
      name: 'User', email: "user-#{SecureRandom.hex(4)}@example.com",
      password: 'password123', password_confirmation: 'password123',
      profile_id: profile_id, client: client
    )
  end

  test 'allows an admin via the selected client in session' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    admin = build_user(admin: true)
    sign_in admin

    post update_selected_client_path, params: { client_id: client.id }
    get crm_path

    assert_response :success
  end

  test 'index shows coupon sales totals for the affiliate within the selected period' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    Profile.find_or_create_by!(id: Profile::AFFILIATE) { |p| p.name = 'Afiliado' }
    affiliate = User.create!(
      name: 'Joao', email: "joao-#{SecureRandom.hex(4)}@example.com",
      password: 'password123', password_confirmation: 'password123',
      profile_id: Profile::AFFILIATE, client: client, utm_code: 'joao123', discount_code: 'JOAO10'
    )
    user = build_user(client: client)
    sign_in user

    # dentro do periodo (hoje), com o cupom do afiliado
    Order.create!(client: client, shopify_order_id: SecureRandom.hex(6), shopify_creation_date: Time.current,
                  subtotal_price: 100, total_discounts: 10, total_price: 90, total_shipping_price: 10,
                  discount_code: 'JOAO10')
    # fora do periodo (mes passado) — nao deve contar
    Order.create!(client: client, shopify_order_id: SecureRandom.hex(6), shopify_creation_date: 2.months.ago,
                  subtotal_price: 500, total_discounts: 50, total_price: 450, total_shipping_price: 0,
                  discount_code: 'JOAO10')
    # com outro cupom — nao deve contar
    Order.create!(client: client, shopify_order_id: SecureRandom.hex(6), shopify_creation_date: Time.current,
                  subtotal_price: 300, total_discounts: 0, total_price: 300, total_shipping_price: 0,
                  discount_code: 'OUTRO')

    get events_path(utm_code: 'joao123', period: '1')

    assert_response :success
    assert_match 'Vendas com o Cupom JOAO10', response.body
    assert_match 'R$ 110,00', response.body
  end

  test 'generate_link builds the URL from the client site_url plus the given path' do
    client = Client.create!(
      name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com",
      site_url: 'https://sualojaexemplo.com.br'
    )
    user = build_user(client: client)
    sign_in user

    post generate_link_events_path, params: { utm_code: 'joao123', path: '/produtos/camiseta' }, as: :json

    body = JSON.parse(response.body)
    assert_equal 'https://sualojaexemplo.com.br/produtos/camiseta?utm_affiliate=joao123', body['link']
  end

  test 'generate_link strips a pasted full URL down to path+query instead of doubling the domain' do
    client = Client.create!(
      name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com",
      site_url: 'https://dunasdn.com'
    )
    user = build_user(client: client)
    sign_in user

    post generate_link_events_path,
         params: { utm_code: 'afan', path: 'https://dunasdn.com/collections/euro-summer' }, as: :json

    body = JSON.parse(response.body)
    assert_equal 'https://dunasdn.com/collections/euro-summer?utm_affiliate=afan', body['link']
  end

  test 'generate_link falls back to the homepage when path is blank' do
    client = Client.create!(
      name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com",
      site_url: 'https://sualojaexemplo.com.br'
    )
    user = build_user(client: client)
    sign_in user

    post generate_link_events_path, params: { utm_code: 'joao123', path: '' }, as: :json

    body = JSON.parse(response.body)
    assert_equal 'https://sualojaexemplo.com.br?utm_affiliate=joao123', body['link']
  end

  test 'generate_link errors when site_url is not configured' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    user = build_user(client: client)
    sign_in user

    post generate_link_events_path, params: { utm_code: 'joao123', path: '' }, as: :json

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_match 'Site principal nao configurado', body['error']
  end
end
