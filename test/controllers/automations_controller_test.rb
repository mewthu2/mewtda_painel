require 'test_helper'

class AutomationsControllerTest < ActionDispatch::IntegrationTest
  def build_user(admin: false, client: nil)
    profile_id = admin ? Profile::ADMIN : Profile::USER
    Profile.find_or_create_by!(id: profile_id) { |p| p.name = admin ? 'Admin' : 'User' }

    User.create!(
      name: 'User', email: "user-#{SecureRandom.hex(4)}@example.com",
      password: 'password123', password_confirmation: 'password123',
      profile_id: profile_id, client: client
    )
  end

  test 'redirects when no client is linked or selected' do
    user = build_user
    sign_in user

    get automations_path

    assert_redirected_to crm_path
  end

  test 'allows a non-admin client user' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    user = build_user(client: client)
    sign_in user

    get automations_path

    assert_response :success
  end

  test 'allows an admin via the selected client in session' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    admin = build_user(admin: true)
    sign_in admin

    post update_selected_client_path, params: { client_id: client.id }
    get automations_path

    assert_response :success
  end

  test 'edit_tracking initializes a not-yet-persisted campaign with tracking defaults' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    user = build_user(client: client)
    sign_in user

    get edit_tracking_automation_path

    assert_response :success
    assert_equal 0, client.campaigns.count
  end

  test 'update_tracking creates the shipping_tracking campaign' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    user = build_user(client: client)
    sign_in user

    patch tracking_automation_path, params: {
      campaign: {
        name: 'Rastreio', message: 'Seu pedido {pedido} saiu, rastreio: {rastreio}',
        start_date: Date.current, end_date: Date.current + 1.year,
        active: '1', max_sends: 3, interval_days: 4
      }
    }

    assert_redirected_to automations_path
    campaign = client.campaigns.find_by(kind: 'shipping_tracking')
    assert campaign.present?
    assert campaign.active?
  end
end
