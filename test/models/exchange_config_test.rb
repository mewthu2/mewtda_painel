require 'test_helper'

class ExchangeConfigTest < ActiveSupport::TestCase
  def build_client(name: 'Loja Teste')
    Client.create!(name: name, email: "loja-#{SecureRandom.hex(4)}@example.com")
  end

  test 'generates a slug from the client name on create' do
    config = ExchangeConfig.create!(client: build_client(name: 'Dunas DN'))
    assert_equal 'dunas-dn', config.slug
  end

  test 'appends the client_id when the slug collides with another client' do
    client_a = build_client(name: 'Loja X')
    client_b = build_client(name: 'Loja X')
    ExchangeConfig.create!(client: client_a)

    config_b = ExchangeConfig.create!(client: client_b)

    assert_equal "loja-x-#{client_b.id}", config_b.slug
  end

  test 'does not overwrite an existing slug on update' do
    config = ExchangeConfig.create!(client: build_client)
    slug = config.slug

    config.update!(company_name: 'Loja Teste')

    assert_equal slug, config.reload.slug
  end

  test 'defaults to inactive, 7 day return window and 30 day coupon validity' do
    config = ExchangeConfig.create!(client: build_client)
    assert_not config.active?
    assert_equal 7, config.return_window_days
    assert_equal 30, config.coupon_validity_days
  end

  test 'requires company_name when active' do
    config = ExchangeConfig.new(client: build_client, active: true)
    assert_not config.valid?
    assert_includes config.errors.attribute_names, :company_name
  end

  test 'allows a blank company_name when inactive' do
    config = ExchangeConfig.new(client: build_client, active: false)
    assert config.valid?, config.errors.full_messages.to_s
  end

  test 'rejects a non-hex accent_color' do
    config = ExchangeConfig.new(client: build_client, accent_color: 'purple')
    assert_not config.valid?
  end

  test 'rejects a zero or negative return_window_days' do
    config = ExchangeConfig.new(client: build_client, return_window_days: 0)
    assert_not config.valid?
  end

  test 'applies default subject/body content for all 4 e-mails on create' do
    config = ExchangeConfig.create!(client: build_client)

    assert_equal 'Recebemos sua solicitação de troca/devolução', config.requested_email_subject
    assert config.requested_email_body.present?
    assert_equal 'Sua solicitação foi aprovada!', config.approved_email_subject
    assert config.approved_email_body.present?
    assert_equal 'Sobre sua solicitação de troca/devolução', config.rejected_email_subject
    assert config.rejected_email_body.present?
    assert_equal 'Sua troca/devolução foi concluída', config.completed_email_subject
    assert config.completed_email_body.present?
  end

  test 'does not override custom email content provided on create' do
    config = ExchangeConfig.create!(client: build_client, requested_email_subject: 'Assunto customizado')
    assert_equal 'Assunto customizado', config.requested_email_subject
  end

  test 'a client has one exchange_config, destroyed with it' do
    client = build_client
    config = ExchangeConfig.create!(client: client)

    client.destroy

    assert_not ExchangeConfig.exists?(config.id)
  end
end
