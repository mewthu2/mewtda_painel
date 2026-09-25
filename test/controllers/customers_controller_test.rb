require 'test_helper'

class CustomersControllerTest < ActionDispatch::IntegrationTest
  def build_user(admin: false, client: nil)
    profile_id = admin ? Profile::ADMIN : Profile::USER
    Profile.find_or_create_by!(id: profile_id) { |p| p.name = admin ? 'Admin' : 'User' }

    User.create!(
      name: 'User', email: "user-#{SecureRandom.hex(4)}@example.com",
      password: 'password123', password_confirmation: 'password123',
      profile_id: profile_id, client: client
    )
  end

  def build_client
    Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
  end

  def build_customer_with_order(client:, email:)
    customer = Customer.create!(email: email, shopify_customer_id: SecureRandom.hex(6))
    Order.create!(
      client: client, customer: customer, shopify_order_id: SecureRandom.hex(6),
      shopify_creation_date: Time.current, total_price: 100, subtotal_price: 100, total_discounts: 0
    )
    customer
  end

  test 'marks a customer as Cadastrado when their e-mail matches a popup submission' do
    client = build_client
    build_customer_with_order(client: client, email: 'ANA@example.com')
    popup = Popup.create!(client: client)
    popup.popup_submissions.create!(name: 'Ana', email: 'ana@example.com', status: 'success')
    user = build_user(client: client)
    sign_in user

    get customers_path

    assert_response :success
    # A coluna "Cadastrado em" (data de cadastro do cliente) já contém a
    # palavra "Cadastrado" — checa o texto exato da badge, não a substring.
    assert_match '>Cadastrado</span>', response.body
  end

  test 'does not mark a customer with no matching popup submission' do
    client = build_client
    build_customer_with_order(client: client, email: 'beto@example.com')
    user = build_user(client: client)
    sign_in user

    get customers_path

    assert_response :success
    assert_no_match '>Cadastrado</span>', response.body
  end
end
