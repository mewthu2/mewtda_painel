require 'test_helper'

class ShopifyAuthControllerTest < ActionDispatch::IntegrationTest
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
    Client.create!(
      name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com",
      shopify_api_key: 'key', shopify_api_secret: 'secret'
    )
  end

  test 'blocks an unauthenticated request' do
    client = build_client

    get client_shopify_auth_path(client, shop: 'loja.myshopify.com')

    assert_redirected_to new_user_session_path
  end

  test 'blocks a client user from triggering OAuth for a different client' do
    own_client = build_client
    other_client = build_client
    user = build_user(client: own_client)
    sign_in user

    get client_shopify_auth_path(other_client, shop: 'outra-loja.myshopify.com')

    assert_redirected_to crm_path
  end

  test 'allows a client user to connect their own client' do
    client = build_client
    user = build_user(client: client)
    sign_in user

    get client_shopify_auth_path(client, shop: 'loja.myshopify.com')

    assert_response :redirect
    assert_match %r{\Ahttps://loja\.myshopify\.com}, response.location
  end

  test 'allows an admin to trigger OAuth for any client' do
    client = build_client
    admin = build_user(admin: true)
    sign_in admin

    get client_shopify_auth_path(client, shop: 'loja.myshopify.com')

    assert_response :redirect
    assert_match %r{\Ahttps://loja\.myshopify\.com}, response.location
  end
end
