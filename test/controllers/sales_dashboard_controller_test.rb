require 'test_helper'

class SalesDashboardControllerTest < ActionDispatch::IntegrationTest
  def build_user(admin: false, client: nil)
    # No profiles.yml fixture exists, so the referenced profile (id 1 = admin,
    # id 2 = regular user, per Profile::ADMIN/Profile::USER) must be created
    # here to satisfy the users.profile_id foreign key constraint.
    profile_id = admin ? Profile::ADMIN : Profile::USER
    Profile.find_or_create_by!(id: profile_id) { |p| p.name = admin ? 'Admin' : 'User' }

    User.create!(
      name: 'User', email: "user-#{SecureRandom.hex(4)}@example.com",
      password: 'password123', password_confirmation: 'password123',
      profile_id: profile_id, client: client
    )
  end

  test 'redirects a non-admin client user when the dashboard is disabled' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com", sales_dashboard_enabled: false)
    user = build_user(client: client)
    sign_in user

    get sales_dashboard_path

    assert_redirected_to crm_path
  end

  test 'allows a non-admin client user when the dashboard is enabled' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com", sales_dashboard_enabled: true)
    user = build_user(client: client)
    sign_in user

    get sales_dashboard_path

    assert_response :success
  end

  test 'always allows an admin regardless of the toggle' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com", sales_dashboard_enabled: false)
    admin = build_user(admin: true, client: client)
    sign_in admin

    get sales_dashboard_path

    assert_response :success
  end

  test 'renders the metrics for the requested month' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com", sales_dashboard_enabled: true)
    user = build_user(client: client)
    Order.create!(client: client, shopify_order_id: SecureRandom.hex(6), shopify_creation_date: Time.zone.local(2026, 3, 10), total_price: 250, subtotal_price: 250, total_discounts: 0)
    sign_in user

    get sales_dashboard_path(year: 2026, month: 3)

    assert_response :success
    assert_match 'R$ 250,00', response.body
  end

  test 'shows a not-synced warning when a platform is configured but has no snapshot yet' do
    client = Client.create!(
      name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com", sales_dashboard_enabled: true,
      meta_access_token: 'token', meta_ad_account_id: 'act_1'
    )
    user = build_user(client: client)
    sign_in user

    get sales_dashboard_path(year: 2026, month: 3)

    assert_response :success
    assert_match 'Custos de anúncio não configurados', response.body
  end

  test 'shows a no-integration warning when no ad platform is configured at all' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com", sales_dashboard_enabled: true)
    user = build_user(client: client)
    sign_in user

    get sales_dashboard_path(year: 2026, month: 3)

    assert_response :success
    assert_match 'Nenhuma integração de anúncio configurada', response.body
  end

  test 'the no-integration warning links a common user to their own settings page' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com", sales_dashboard_enabled: true)
    user = build_user(client: client)
    sign_in user

    get sales_dashboard_path(year: 2026, month: 3)

    assert_response :success
    assert_match %r{href="#{Regexp.escape(edit_settings_path)}"}, response.body
  end

  test 'the no-integration warning links an admin to the client edit page' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com", sales_dashboard_enabled: true)
    admin = build_user(admin: true, client: client)
    sign_in admin

    get sales_dashboard_path(year: 2026, month: 3)

    assert_response :success
    assert_match %r{href="#{Regexp.escape(edit_client_path(client))}"}, response.body
  end

  test 'blocks a non-admin from triggering sync_ad_costs even when the dashboard is enabled' do
    client = Client.create!(
      name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com", sales_dashboard_enabled: true,
      meta_access_token: 'token', meta_ad_account_id: 'act_1'
    )
    user = build_user(client: client)
    sign_in user

    post sync_ad_costs_sales_dashboard_path

    assert_redirected_to crm_path
  end

  test 'does not crash on an out-of-range month param' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com", sales_dashboard_enabled: true)
    user = build_user(client: client)
    sign_in user

    get sales_dashboard_path(year: 2026, month: 99)

    assert_response :success
  end
end
