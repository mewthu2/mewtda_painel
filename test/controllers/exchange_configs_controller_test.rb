require 'test_helper'

class ExchangeConfigsControllerTest < ActionDispatch::IntegrationTest
  def build_client
    Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
  end

  def build_user(client:)
    Profile.find_or_create_by!(id: Profile::USER) { |p| p.name = 'User' }
    User.create!(
      name: 'User', email: "user-#{SecureRandom.hex(4)}@example.com",
      password: 'password123', password_confirmation: 'password123', profile_id: Profile::USER, client: client
    )
  end

  test 'edit builds a new config when none exists yet' do
    sign_in build_user(client: build_client)
    get edit_exchange_config_path
    assert_response :success
  end

  test 'update saves the branding, window and e-mail fields' do
    client = build_client
    sign_in build_user(client: client)

    patch exchange_config_path, params: {
      exchange_config: {
        active: '1', company_name: 'Loja Teste', return_window_days: 10, coupon_validity_days: 20,
        requested_email_subject: 'Recebemos!', requested_email_body: 'Olá {{customer_name}}'
      }
    }

    assert_redirected_to edit_exchange_config_path
    config = client.reload.exchange_config
    assert config.active?
    assert_equal 10, config.return_window_days
    assert_equal 'Recebemos!', config.requested_email_subject
  end

  test 'update re-renders the form when invalid' do
    sign_in build_user(client: build_client)

    patch exchange_config_path, params: { exchange_config: { active: '1', company_name: '' } }

    assert_response :unprocessable_entity
  end

  test 'email_templates renders the dedicated e-mail templates screen' do
    sign_in build_user(client: build_client)
    get email_templates_exchange_config_path
    assert_response :success
  end

  test 'update with return_to email_templates redirects back to the e-mail templates screen' do
    client = build_client
    sign_in build_user(client: client)

    patch exchange_config_path, params: {
      return_to: 'email_templates',
      exchange_config: { requested_email_subject: 'Recebemos!' }
    }

    assert_redirected_to email_templates_exchange_config_path
    assert_equal 'Recebemos!', client.reload.exchange_config.requested_email_subject
  end

  test 'update with return_to email_templates re-renders that screen when invalid' do
    sign_in build_user(client: build_client)

    patch exchange_config_path, params: {
      return_to: 'email_templates',
      exchange_config: { active: '1', company_name: '' }
    }

    assert_response :unprocessable_entity
  end

  test 'update purges the requested_email_image when the remove flag is set' do
    client = build_client
    config = client.create_exchange_config!
    config.requested_email_image.attach(io: StringIO.new('fake image data'), filename: 'test.png', content_type: 'image/png')
    sign_in build_user(client: client)

    patch exchange_config_path, params: {
      return_to: 'email_templates',
      exchange_config: { remove_requested_email_image: '1' }
    }

    assert_not config.reload.requested_email_image.attached?
  end
end
