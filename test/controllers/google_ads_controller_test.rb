require 'test_helper'
require 'minitest/mock'

class GoogleAdsControllerTest < ActionDispatch::IntegrationTest
  FakeResponse = Struct.new(:success?, :parsed_response)

  def build_admin
    # No profiles.yml fixture exists, so the admin profile (id 1, referenced by
    # User#admin? via profile_id == 1) must be created here to satisfy the
    # users.profile_id foreign key constraint.
    admin_profile = Profile.find_or_create_by!(id: Profile::ADMIN) { |p| p.name = 'Admin' }

    User.create!(
      name: 'Admin', email: "admin-#{SecureRandom.hex(4)}@example.com",
      password: 'password123', password_confirmation: 'password123', profile_id: admin_profile.id
    )
  end

  def build_client
    Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
  end

  def build_user(client: nil)
    Profile.find_or_create_by!(id: Profile::USER) { |p| p.name = 'User' }

    User.create!(
      name: 'User', email: "user-#{SecureRandom.hex(4)}@example.com",
      password: 'password123', password_confirmation: 'password123',
      profile_id: Profile::USER, client: client
    )
  end

  test 'connect redirects to Google OAuth consent screen with a signed state' do
    admin = build_admin
    client = build_client
    sign_in admin

    get client_google_ads_connect_path(client)

    assert_response :redirect
    assert_match %r{\Ahttps://accounts\.google\.com/o/oauth2/v2/auth}, response.location
  end

  test 'callback stores the refresh token and marks the client as connected' do
    admin = build_admin
    client = build_client
    sign_in admin

    state = Rails.application.message_verifier(:google_ads_oauth_state).generate(client.id)
    response_double = FakeResponse.new(true, { 'refresh_token' => 'refresh-abc' })

    HTTParty.stub :post, response_double do
      get google_ads_callback_url(code: 'auth-code', state: state)
    end

    assert_redirected_to edit_client_path(client)
    client.reload
    assert_equal 'refresh-abc', client.google_ads_refresh_token
    assert client.google_ads_connected_at.present?
  end

  test 'callback rejects an invalid state' do
    admin = build_admin
    sign_in admin

    get google_ads_callback_url(code: 'auth-code', state: 'tampered')

    assert_redirected_to clients_path
    assert_equal 'Estado inválido na conexão com o Google Ads.', flash[:alert]
  end

  test 'a common user can connect Google Ads for their own client' do
    client = build_client
    user = build_user(client: client)
    sign_in user

    get client_google_ads_connect_path(client)

    assert_response :redirect
    assert_match %r{\Ahttps://accounts\.google\.com/o/oauth2/v2/auth}, response.location
  end

  test 'a common user cannot connect Google Ads for another client' do
    client = build_client
    other_client = build_client
    user = build_user(client: client)
    sign_in user

    get client_google_ads_connect_path(other_client)

    assert_redirected_to root_path
  end

  test 'callback redirects a common user to their own settings page' do
    client = build_client
    user = build_user(client: client)
    sign_in user

    state = Rails.application.message_verifier(:google_ads_oauth_state).generate(client.id)
    response_double = FakeResponse.new(true, { 'refresh_token' => 'refresh-abc' })

    HTTParty.stub :post, response_double do
      get google_ads_callback_url(code: 'auth-code', state: state)
    end

    assert_redirected_to edit_settings_path
    client.reload
    assert_equal 'refresh-abc', client.google_ads_refresh_token
  end

  test 'callback rejects a common user completing another client state' do
    client = build_client
    other_client = build_client
    user = build_user(client: client)
    sign_in user

    state = Rails.application.message_verifier(:google_ads_oauth_state).generate(other_client.id)

    get google_ads_callback_url(code: 'auth-code', state: state)

    assert_redirected_to root_path
    assert_nil other_client.reload.google_ads_refresh_token
  end

  test 'a common user can disconnect Google Ads for their own client' do
    client = build_client
    client.update!(google_ads_refresh_token: 'refresh-abc', google_ads_connected_at: Time.current)
    user = build_user(client: client)
    sign_in user

    delete client_google_ads_disconnect_path(client)

    assert_redirected_to edit_settings_path
    assert_nil client.reload.google_ads_refresh_token
  end

  test 'disconnect clears the stored refresh token' do
    admin = build_admin
    client = build_client
    client.update!(google_ads_refresh_token: 'refresh-abc', google_ads_connected_at: Time.current)
    sign_in admin

    delete client_google_ads_disconnect_path(client)

    assert_redirected_to edit_client_path(client)
    client.reload
    assert_nil client.google_ads_refresh_token
    assert_nil client.google_ads_connected_at
  end
end
