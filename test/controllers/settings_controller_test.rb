require 'test_helper'

class SettingsControllerTest < ActionDispatch::IntegrationTest
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

  test 'a user without a linked client is redirected with an alert' do
    user = build_user
    sign_in user

    get edit_settings_path

    assert_redirected_to crm_path
    assert_equal 'Você não está vinculado a nenhum cliente.', flash[:alert]
  end

  test 'a common user can view their own client settings' do
    client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
    user = build_user(client: client)
    sign_in user

    get edit_settings_path

    assert_response :success
    assert_match client.name, response.body
  end

  test 'a common user can update Meta Ads and Google Ads fields for their own client' do
    client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
    user = build_user(client: client)
    sign_in user

    patch settings_path, params: {
      client: {
        name: client.name,
        email: client.email,
        meta_access_token: 'token123',
        meta_ad_account_id: 'act_1',
        google_ads_customer_id: '1234567890'
      }
    }

    assert_redirected_to edit_settings_path
    client.reload
    assert_equal 'token123', client.meta_access_token
    assert_equal 'act_1', client.meta_ad_account_id
    assert_equal '1234567890', client.google_ads_customer_id
  end

  test 'a common user cannot change the active flag of their own client' do
    client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com", active: true)
    user = build_user(client: client)
    sign_in user

    patch settings_path, params: {
      client: { name: client.name, email: client.email, active: '0' }
    }

    assert client.reload.active?
  end

  test 'a common user always edits their own client no matter what other client exists' do
    other_client = Client.create!(name: 'Outra Loja', email: "outra-#{SecureRandom.hex(4)}@example.com")
    client = Client.create!(name: 'Minha Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    user = build_user(client: client)
    sign_in user

    get edit_settings_path

    assert_response :success
    assert_match 'Minha Loja', response.body
    assert_no_match 'Outra Loja', response.body
  end

  test 'a common user does not see the active toggle or linked users list' do
    client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
    user = build_user(client: client)
    sign_in user

    get edit_settings_path

    assert_response :success
    assert_no_match 'Cliente ativo', response.body
    assert_no_match 'Usuários Vinculados', response.body
  end

  test 'submitting a blank meta_access_token preserves the existing stored token' do
    client = Client.create!(
      name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com",
      meta_access_token: 'existing-token', meta_ad_account_id: 'act_1'
    )
    user = build_user(client: client)
    sign_in user

    patch settings_path, params: {
      client: { name: client.name, email: client.email, meta_access_token: '' }
    }

    assert_equal 'existing-token', client.reload.meta_access_token
  end
end
