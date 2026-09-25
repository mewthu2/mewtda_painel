require 'test_helper'

class EmailTemplateTest < ActiveSupport::TestCase
  def build_client
    Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
  end

  def valid_attributes(overrides = {})
    {
      client: build_client,
      name: 'Boas-vindas padrão',
      subject: 'Seja bem-vindo(a)!',
      heading: 'Bem-vindo(a)!',
      body: 'Que bom ter você com a gente.',
      button_text: 'Ver produtos'
    }.merge(overrides)
  end

  test 'valid with required fields and defaults' do
    template = EmailTemplate.new(valid_attributes)
    assert template.valid?, template.errors.full_messages.to_s
  end

  test 'requires name, subject, heading, body and button_text' do
    template = EmailTemplate.new(client: build_client)

    assert_not template.valid?
    assert_includes template.errors.attribute_names, :name
    assert_includes template.errors.attribute_names, :subject
    assert_includes template.errors.attribute_names, :heading
    assert_includes template.errors.attribute_names, :body
    assert_includes template.errors.attribute_names, :button_text
  end

  test 'defaults to manual trigger_kind and image_top layout' do
    template = EmailTemplate.create!(valid_attributes)
    assert template.manual?
    assert_equal 'image_top', template.layout
  end

  test 'rejects an unknown layout' do
    template = EmailTemplate.new(valid_attributes(layout: 'sideways'))
    assert_not template.valid?
  end

  test 'accepts the image_top_bottom layout' do
    template = EmailTemplate.new(valid_attributes(layout: 'image_top_bottom'))
    assert template.valid?, template.errors.full_messages.to_s
  end

  test 'rejects a non-hex accent_color' do
    template = EmailTemplate.new(valid_attributes(accent_color: 'purple'))
    assert_not template.valid?
  end

  test 'cart_recovery requires trigger_delay_hours' do
    template = EmailTemplate.new(valid_attributes(trigger_kind: :cart_recovery))
    assert_not template.valid?
    assert_includes template.errors.attribute_names, :trigger_delay_hours

    template.trigger_delay_hours = 2
    assert template.valid?, template.errors.full_messages.to_s
  end

  test 'inactive_customer requires trigger_inactive_days' do
    template = EmailTemplate.new(valid_attributes(trigger_kind: :inactive_customer))
    assert_not template.valid?
    assert_includes template.errors.attribute_names, :trigger_inactive_days

    template.trigger_inactive_days = 30
    assert template.valid?, template.errors.full_messages.to_s
  end

  test 'post_purchase requires trigger_days_after_purchase' do
    template = EmailTemplate.new(valid_attributes(trigger_kind: :post_purchase))
    assert_not template.valid?
    assert_includes template.errors.attribute_names, :trigger_days_after_purchase

    template.trigger_days_after_purchase = 3
    assert template.valid?, template.errors.full_messages.to_s
  end

  test 'welcome and cashback need no extra trigger config' do
    assert EmailTemplate.new(valid_attributes(trigger_kind: :welcome)).valid?
    assert EmailTemplate.new(valid_attributes(trigger_kind: :cashback)).valid?
  end

  test 'preset returns prefilled attributes for a known key' do
    preset = EmailTemplate.preset(:cart_recovery)

    assert_equal 'image_left', preset[:layout]
    assert_equal 'cart_recovery', preset[:trigger_kind]
    assert_equal 2, preset[:trigger_config]['delay_hours']
    assert preset[:subject].present?
  end

  test 'preset returns nil for an unknown key' do
    assert_nil EmailTemplate.preset(:not_a_real_preset)
  end

  test 'preset returns nil for a blank key' do
    assert_nil EmailTemplate.preset(nil)
    assert_nil EmailTemplate.preset('')
  end

  test 'a client can have many email templates, destroyed with it' do
    client = build_client
    template = EmailTemplate.create!(valid_attributes(client: client))

    client.destroy

    assert_not EmailTemplate.exists?(template.id)
  end
end
