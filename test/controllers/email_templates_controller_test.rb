require 'test_helper'

class EmailTemplatesControllerTest < ActionDispatch::IntegrationTest
  def build_user(client:)
    Profile.find_or_create_by!(id: Profile::USER) { |p| p.name = 'User' }

    User.create!(
      name: 'User', email: "user-#{SecureRandom.hex(4)}@example.com",
      password: 'password123', password_confirmation: 'password123',
      profile_id: Profile::USER, client: client
    )
  end

  def build_client
    Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
  end

  def valid_params
    {
      name: 'Boas-vindas', subject: 'Oi!', heading: 'Bem-vindo(a)!',
      body: 'Texto', button_text: 'Ver produtos'
    }
  end

  test 'index lists only the current client templates' do
    client = build_client
    other_client = build_client
    EmailTemplate.create!(valid_params.merge(client: client))
    EmailTemplate.create!(valid_params.merge(client: other_client, name: 'De outro cliente'))
    sign_in build_user(client: client)

    get email_templates_path

    assert_response :success
    assert_match 'Boas-vindas', response.body
    assert_no_match 'De outro cliente', response.body
  end

  test 'new without a preset renders a blank form' do
    sign_in build_user(client: build_client)

    get new_email_template_path

    assert_response :success
  end

  test 'new prefills attributes from a preset' do
    sign_in build_user(client: build_client)

    get new_email_template_path(preset: 'cart_recovery')

    assert_response :success
    assert_match 'Carrinho abandonado', response.body
  end

  test 'create saves a template scoped to the current client' do
    client = build_client
    sign_in build_user(client: client)

    assert_difference 'EmailTemplate.count', 1 do
      post email_templates_path, params: { email_template: valid_params }
    end

    assert_equal client, EmailTemplate.last.client
    assert_redirected_to email_templates_path
  end

  test 'create re-renders the form with errors when invalid' do
    sign_in build_user(client: build_client)

    assert_no_difference 'EmailTemplate.count' do
      post email_templates_path, params: { email_template: valid_params.merge(name: '') }
    end

    assert_response :unprocessable_entity
  end

  test 'update changes an existing template' do
    client = build_client
    template = EmailTemplate.create!(valid_params.merge(client: client))
    sign_in build_user(client: client)

    patch email_template_path(template), params: { email_template: { name: 'Novo nome' } }

    assert_redirected_to email_templates_path
    assert_equal 'Novo nome', template.reload.name
  end

  test 'update removes the image when remove_image is checked' do
    client = build_client
    template = EmailTemplate.create!(valid_params.merge(client: client))
    template.image.attach(io: StringIO.new('fake'), filename: 'banner.png', content_type: 'image/png')
    sign_in build_user(client: client)

    patch email_template_path(template), params: { email_template: { remove_image: '1' } }

    assert_not template.reload.image.attached?
  end

  test 'update removes the bottom image when remove_image_bottom is checked' do
    client = build_client
    template = EmailTemplate.create!(valid_params.merge(client: client))
    template.image_bottom.attach(io: StringIO.new('fake'), filename: 'banner.png', content_type: 'image/png')
    sign_in build_user(client: client)

    patch email_template_path(template), params: { email_template: { remove_image_bottom: '1' } }

    assert_not template.reload.image_bottom.attached?
  end

  test 'destroy removes the template' do
    client = build_client
    template = EmailTemplate.create!(valid_params.merge(client: client))
    sign_in build_user(client: client)

    assert_difference 'EmailTemplate.count', -1 do
      delete email_template_path(template)
    end
  end

  test 'cannot edit a template belonging to another client' do
    other_client = build_client
    template = EmailTemplate.create!(valid_params.merge(client: other_client))
    sign_in build_user(client: build_client)

    get edit_email_template_path(template)

    assert_redirected_to email_templates_path
  end
end
