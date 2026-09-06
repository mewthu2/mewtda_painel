require 'test_helper'

class PopupTest < ActiveSupport::TestCase
  def build_client
    Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
  end

  test 'valid with defaults and inactive' do
    popup = Popup.new(client: build_client)
    assert popup.valid?
  end

  test 'generates a unique public_token on create' do
    popup = Popup.create!(client: build_client)
    assert popup.public_token.present?

    other = Popup.create!(client: build_client)
    assert_not_equal popup.public_token, other.public_token
  end

  test 'requires title, coupon_code and button_text when active' do
    popup = Popup.new(client: build_client, active: true)

    I18n.with_locale(:en) do
      assert_not popup.valid?
      assert_includes popup.errors[:title], "can't be blank"
      assert_includes popup.errors[:coupon_code], "can't be blank"
    end
  end

  test 'valid when active with title, coupon_code and button_text present' do
    popup = Popup.new(
      client: build_client, active: true,
      title: 'Ganhe 10%', coupon_code: 'BEMVINDO10', button_text: 'Cadastrar'
    )
    assert popup.valid?
  end

  test 'rejects an unknown template' do
    popup = Popup.new(client: build_client, template: 'template_9')
    assert_not popup.valid?
  end

  test 'rejects an unknown size' do
    popup = Popup.new(client: build_client, size: 'huge')
    assert_not popup.valid?
  end

  test 'rejects a non-hex accent_color' do
    popup = Popup.new(client: build_client, accent_color: 'purple')
    assert_not popup.valid?
  end

  test 'rejects reappear_after_hours below 1' do
    popup = Popup.new(client: build_client, reappear_after_hours: 0)
    assert_not popup.valid?
  end

  test 'a client has one popup' do
    client = build_client
    popup = Popup.create!(client: client)

    assert_equal popup, client.reload.popup
  end
end
