require 'test_helper'

class PopupSubmissionTest < ActiveSupport::TestCase
  def build_popup
    client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
    Popup.create!(client: client)
  end

  test 'valid with name, email and a known status' do
    submission = PopupSubmission.new(popup: build_popup, name: 'Ana', email: 'ana@example.com', status: 'success')
    assert submission.valid?
  end

  test 'invalid without a name' do
    submission = PopupSubmission.new(popup: build_popup, email: 'ana@example.com', status: 'success')
    assert_not submission.valid?
  end

  test 'invalid without an email' do
    submission = PopupSubmission.new(popup: build_popup, name: 'Ana', status: 'success')
    assert_not submission.valid?
  end

  test 'invalid with an unknown status' do
    submission = PopupSubmission.new(popup: build_popup, name: 'Ana', email: 'ana@example.com', status: 'pending')
    assert_not submission.valid?
  end

  test 'a popup has many submissions' do
    popup = build_popup
    submission = PopupSubmission.create!(popup: popup, name: 'Ana', email: 'ana@example.com', status: 'success')

    assert_includes popup.popup_submissions, submission
  end

  test 'is not integrated without a shopify_customer_id' do
    submission = PopupSubmission.new(popup: build_popup, name: 'Ana', email: 'ana@example.com', status: 'shopify_error')

    assert_not submission.integrated?
    assert_nil submission.shopify_admin_customer_url
  end

  test 'builds the Shopify admin customer URL from the GID and the client shop handle' do
    client = Client.create!(
      name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com",
      shopify_shop_url: 'loja-teste.myshopify.com'
    )
    popup = Popup.create!(client: client)
    submission = PopupSubmission.create!(
      popup: popup, name: 'Ana', email: 'ana@example.com', status: 'success',
      shopify_customer_id: 'gid://shopify/Customer/123456'
    )

    assert submission.integrated?
    assert_equal 'https://admin.shopify.com/store/loja-teste/customers/123456', submission.shopify_admin_customer_url
  end

  test 'has no admin URL when integrated but the client has no shop configured' do
    submission = PopupSubmission.create!(
      popup: build_popup, name: 'Ana', email: 'ana@example.com', status: 'success',
      shopify_customer_id: 'gid://shopify/Customer/123456'
    )

    assert submission.integrated?
    assert_nil submission.shopify_admin_customer_url
  end
end
