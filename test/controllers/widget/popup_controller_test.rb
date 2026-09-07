require 'test_helper'

class Widget::PopupControllerTest < ActionDispatch::IntegrationTest
  def build_client
    Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
  end

  test 'config returns active false for an unknown token' do
    get widget_popup_config_path(token: 'does-not-exist')

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal false, body['active']
  end

  test 'config returns active false for an inactive popup' do
    popup = Popup.create!(client: build_client, active: false)

    get widget_popup_config_path(token: popup.public_token)

    body = JSON.parse(response.body)
    assert_equal false, body['active']
  end

  test 'config returns the public fields for an active popup' do
    popup = Popup.create!(
      client: build_client, active: true, title: 'Ganhe 10%', description: 'Cadastre-se',
      coupon_code: 'BEMVINDO10', button_text: 'Quero', accent_color: '#ff0000',
      template: 'template_2', size: 'large', reappear_after_hours: 48
    )

    get widget_popup_config_path(token: popup.public_token)

    body = JSON.parse(response.body)
    assert_equal true, body['active']
    assert_equal 'Ganhe 10%', body['title']
    assert_equal 'template_2', body['template']
    assert_equal 48, body['reappear_after_hours']
    assert_not body.key?('coupon_code')
  end

  def fake_customer_creator(result)
    double = Object.new
    double.define_singleton_method(:call) { |**_args| result }
    ->(_db_client) { double }
  end

  test 'create_submission returns 404 for an inactive popup' do
    popup = Popup.create!(client: build_client, active: false)

    post widget_popup_submissions_path, params: { token: popup.public_token, name: 'Ana', email: 'ana@example.com', phone: '11999998888' }

    assert_response :not_found
  end

  test 'create_submission returns 422 without a name or email' do
    popup = Popup.create!(
      client: build_client, active: true, title: 'T', coupon_code: 'C', button_text: 'B'
    )

    post widget_popup_submissions_path, params: { token: popup.public_token, name: '', email: '', phone: '' }

    assert_response :unprocessable_entity
  end

  test 'create_submission logs a success and returns the coupon code' do
    popup = Popup.create!(
      client: build_client, active: true, title: 'T', coupon_code: 'BEMVINDO10', button_text: 'B'
    )
    created = nil

    Shopify::CreateCustomer.stub :new, fake_customer_creator({ ok: true, customer_id: 'gid://shopify/Customer/1' }) do
      post widget_popup_submissions_path, params: { token: popup.public_token, name: 'Ana', email: 'ana@example.com', phone: '11999998888' }
      created = popup.popup_submissions.last
    end

    assert_response :success
    assert_equal 'BEMVINDO10', JSON.parse(response.body)['coupon_code']
    assert_equal 'success', created.status
    assert_equal 'gid://shopify/Customer/1', created.shopify_customer_id
  end

  test 'create_submission still returns the coupon and logs shopify_error when Shopify creation fails' do
    popup = Popup.create!(
      client: build_client, active: true, title: 'T', coupon_code: 'BEMVINDO10', button_text: 'B'
    )
    created = nil

    Shopify::CreateCustomer.stub :new, fake_customer_creator({ ok: false, customer_id: nil }) do
      post widget_popup_submissions_path, params: { token: popup.public_token, name: 'Ana', email: 'ana@example.com', phone: '11999998888' }
      created = popup.popup_submissions.last
    end

    assert_response :success
    assert_equal 'BEMVINDO10', JSON.parse(response.body)['coupon_code']
    assert_equal 'shopify_error', created.status
  end
end
