require 'test_helper'

class LandingPageTest < ActiveSupport::TestCase
  def build_client(name: 'HENRRI')
    Client.create!(name: name, email: "loja-#{SecureRandom.hex(4)}@example.com")
  end

  def build_page(client, attrs = {})
    client.landing_pages.new({ name: 'Drop 01', slug: 'drop-01', template: 'drop_01_1822' }.merge(attrs))
  end

  test 'client gets a slug from its name, unique across clients' do
    first = build_client(name: 'Loja Ração')
    second = build_client(name: 'Loja Ração')

    assert_equal 'loja-racao', first.slug
    assert_equal 'loja-racao-2', second.slug
  end

  test 'client slug cannot be a reserved prefix' do
    client = build_client
    client.slug = 'crm'

    assert_not client.valid?
    assert client.errors[:slug].any?
  end

  test 'path_prefix defaults to the client slug and builds the public path' do
    page = build_page(build_client)
    page.save!

    assert_equal 'henrri', page.path_prefix
    assert_equal '/henrri/drop-01', page.public_path
  end

  test 'path_prefix can be neutral and must not be reserved' do
    client = build_client
    assert build_page(client, path_prefix: 'use1822').valid?

    page = build_page(client, path_prefix: 'widget')
    assert_not page.valid?
    assert page.errors[:path_prefix].any?
  end

  test 'slug is unique per path_prefix only' do
    client = build_client
    build_page(client, path_prefix: 'use1822').save!

    assert_not build_page(client, path_prefix: 'use1822').valid?
    assert build_page(client, path_prefix: 'outra').valid?
  end

  test 'rejects slugs with uppercase, spaces or accents' do
    page = build_page(build_client, slug: 'Drop 01')
    assert_not page.valid?
    assert page.errors[:slug].any?
  end

  test 'template must exist in app/views/landing_pages/templates' do
    assert_includes LandingPage.templates, 'drop_01_1822'
    assert_not build_page(build_client, template: 'nao_existe').valid?
  end

  test 'product handles come from free text, normalized' do
    page = build_page(build_client, product_handles_text: "Camiseta-Branca, camiseta-preta\n\ncamiseta-preta")
    page.valid?

    assert_equal %w[camiseta-branca camiseta-preta], page.product_handles
  end

  test 'sales are open until ends_at' do
    page = build_page(build_client)
    assert page.sales_open?

    page.ends_at = 1.hour.from_now
    assert page.sales_open?

    page.ends_at = 1.minute.ago
    assert_not page.sales_open?
  end

  test 'accepts the Shopify admin product link, a numeric id or a handle as product reference' do
    page = build_page(build_client, product_handles_text: <<~TEXT)
      https://admin.shopify.com/store/henrribrasil/products/10790042206502
      10790042206503
      Camiseta-Ladrao
    TEXT
    page.valid?

    assert_equal ['gid://shopify/Product/10790042206502', 'gid://shopify/Product/10790042206503', 'camiseta-ladrao'],
                 page.product_handles
  end
end
