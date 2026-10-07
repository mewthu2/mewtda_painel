require 'test_helper'

class LandingPages::RegisterLeadTest < ActiveSupport::TestCase
  class FakeShopifyClient
    attr_reader :queries

    def initialize(&block)
      @block = block
      @queries = []
    end

    def query(graphql_query)
      @queries << graphql_query
      @block.call(graphql_query)
    end
  end

  setup do
    @client = Client.create!(
      name: 'HENRRI', email: "loja-#{SecureRandom.hex(4)}@example.com",
      shopify_shop_url: 'henrri.myshopify.com', shopify_access_token: 'token123'
    )
    @page = @client.landing_pages.create!(name: 'Drop 01', path_prefix: 'use1822', slug: 'drop-01',
                                          template: 'drop_01_1822')
  end

  def register(fake, **args)
    Shopify::Client.stub :new, fake do
      LandingPages::RegisterLead.new(@page).call(
        **{ name: 'Ana Silva', email: 'Ana@Example.com', phone: '(31) 99999-8888' }.merge(args)
      )
    end
  end

  test 'creates the Shopify customer with the page tag when the person is not in the base' do
    fake = FakeShopifyClient.new do |query|
      if query.include?('customers(')
        { 'customers' => { 'edges' => [] } }
      else
        { 'customerCreate' => { 'customer' => { 'id' => 'gid://shopify/Customer/1' }, 'userErrors' => [] } }
      end
    end

    result = register(fake, utms: { 'utm_source' => 'instagram', 'evil' => 'x' })

    assert result.created
    lead = result.lead
    assert_equal 'ana@example.com', lead.email
    assert_equal false, lead.existing_customer
    assert_equal 'success', lead.status
    assert_equal 'gid://shopify/Customer/1', lead.shopify_customer_id
    assert_equal 'instagram', lead.utm_source

    create = fake.queries.find { |q| q.include?('customerCreate') }
    assert_includes create, '"lp-use1822-drop-01"'
    assert_includes create, '"+5531999998888"'
  end

  test 'only tags the existing Shopify customer when the e-mail is already in the base' do
    fake = FakeShopifyClient.new do |query|
      if query.include?('customers(')
        { 'customers' => { 'edges' => [{ 'node' => { 'id' => 'gid://shopify/Customer/9' } }] } }
      else
        { 'tagsAdd' => { 'userErrors' => [] } }
      end
    end

    result = register(fake)

    assert result.created
    assert result.lead.existing_customer
    assert_equal 'gid://shopify/Customer/9', result.lead.shopify_customer_id
    assert(fake.queries.none? { |q| q.include?('customerCreate') })
    assert(fake.queries.any? { |q| q.include?('tagsAdd') && q.include?('lp-use1822-drop-01') })
  end

  test 'does not duplicate a lead for the same page and e-mail' do
    fake = FakeShopifyClient.new do |query|
      if query.include?('customers(')
        { 'customers' => { 'edges' => [] } }
      else
        { 'customerCreate' => { 'customer' => { 'id' => 'gid://shopify/Customer/1' }, 'userErrors' => [] } }
      end
    end

    register(fake)
    calls = fake.queries.size
    second = register(fake, email: 'ana@example.com')

    assert_not second.created
    assert_equal 1, @page.leads.count
    assert_equal calls, fake.queries.size
  end

  test 'records the lead with shopify_error when the Shopify API fails' do
    fake = FakeShopifyClient.new { |_q| raise StandardError, 'boom' }

    result = register(fake)

    assert result.created
    assert_equal 'shopify_error', result.lead.status
  end

  test 'returns an invalid lead without calling Shopify when the e-mail is bad' do
    fake = FakeShopifyClient.new { |_q| flunk 'should not call Shopify' }

    result = register(fake, email: 'nao-e-email')

    assert_not result.created
    assert result.lead.errors[:email].any?
  end
end
