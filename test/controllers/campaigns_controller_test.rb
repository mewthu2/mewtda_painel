require 'test_helper'

class CampaignsControllerTest < ActionDispatch::IntegrationTest
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

    get campaigns_path

    assert_redirected_to crm_path
  end

  test 'allows an admin via the selected client in session' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    admin = build_user(admin: true)
    sign_in admin

    post update_selected_client_path, params: { client_id: client.id }
    get campaigns_path

    assert_response :success
  end

  test 'allows a non-admin client user' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    user = build_user(client: client)
    sign_in user

    get campaigns_path

    assert_response :success
  end
end
