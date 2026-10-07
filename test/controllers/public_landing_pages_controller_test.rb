require 'test_helper'

class PublicLandingPagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @client = Client.create!(name: 'HENRRI', email: "loja-#{SecureRandom.hex(4)}@example.com")
    @page = @client.landing_pages.create!(name: 'Drop 01', path_prefix: 'use1822', slug: 'drop-01',
                                          template: 'drop_01_1822', active: true)
  end

  test 'renders an active page by prefix and slug and counts the visit' do
    get '/use1822/drop-01'

    assert_response :success
    assert_match 'Independência se veste.', response.body
    assert_match 'Produzido por HENRRI', response.body
    assert_match 'href="https://www.instagram.com/henrriclothing/"', response.body
    assert_match 'href="https://henrri.com.br/"', response.body
    assert_match 'data-chain', response.body
    assert_match 'O Brasil decidiu andar', response.body
    assert_equal 1, @page.reload.views_count
  end

  test 'uses red only on the breaking chain' do
    get '/use1822/drop-01'

    body = response.body
    chain_svg = body[%r{<svg class="chain__svg".*?</svg>}m]
    outside = body.sub(chain_svg, '').gsub(/--vermelho: #D9272E;.*$/i, '').gsub(/var\(--vermelho\)/, '')
    assert_match(/#D9272E/i, chain_svg)
    assert_no_match(/#D9272E/i, outside)
    # .chain__link, .chain__bar e o ícone da corrente no selo (path + rect)
    assert_equal 4, body.scan('var(--vermelho)').size
  end

  test 'returns 404 for an unknown page' do
    get '/use1822/nao-existe'
    assert_response :not_found
  end

  test 'returns 404 for an inactive page to visitors, without counting the visit' do
    @page.update!(active: false)

    get '/use1822/drop-01'

    assert_response :not_found
    assert_equal 0, @page.reload.views_count
  end

  test 'lets the owner preview an inactive page' do
    @page.update!(active: false)
    Profile.find_or_create_by!(id: Profile::USER) { |p| p.name = 'User' }
    user = User.create!(name: 'U', email: "u-#{SecureRandom.hex(4)}@example.com", password: 'password123',
                        password_confirmation: 'password123', profile_id: Profile::USER, client: @client)
    sign_in user

    get '/use1822/drop-01'

    assert_response :success
    assert_match 'Pré-visualização', response.body
    assert_equal 0, @page.reload.views_count
  end

  test 'shows sales closed after ends_at' do
    @page.update!(ends_at: 1.hour.ago)

    get '/use1822/drop-01'

    assert_response :success
    assert_match 'Pré-venda encerrada', response.body
  end

  test 'sends the campaign end to the page so an open tab stops selling when it passes' do
    ends_at = Time.zone.local(2030, 10, 7, 23, 59)
    @page.update!(ends_at: ends_at)

    get '/use1822/drop-01'

    assert_response :success
    assert_match %("endsAt":#{(ends_at.to_f * 1000).to_i}), response.body
    assert_match 'A campanha acabou em 07/10 às 23:59. As vendas estão encerradas.', response.body
  end

  test 'does not shadow the CRM routes' do
    get '/crm/landing-pages'
    assert_response :redirect # login do Devise, não a landing page
  end

  test 'registers a lead' do
    result = LandingPages::RegisterLead::Result.new(lead: @page.leads.create!(name: 'Ana', email: 'ana@example.com', status: 'success'), created: true)
    fake = Minitest::Mock.new
    fake.expect(:call, result, [], name: 'Ana', email: 'ana@example.com', phone: '', utms: { 'utm_source' => 'ig' })

    LandingPages::RegisterLead.stub :new, ->(_page) { fake } do
      post '/use1822/drop-01/lead', params: { name: 'Ana', email: 'ana@example.com', phone: '', utm_source: 'ig' }
    end

    assert_response :success
    assert_equal true, response.parsed_body['ok']
    fake.verify
  end

  test 'honeypot submissions are accepted silently and not stored' do
    post '/use1822/drop-01/lead', params: { name: 'Bot', email: 'bot@example.com', website: 'http://spam' }

    assert_response :success
    assert_equal 0, @page.leads.count
  end

  test 'renders the kit builder (1 to 4) with the product options' do
    product = {
      'id' => 'gid://shopify/Product/1', 'title' => 'Camiseta Ladrão', 'availableForSale' => true,
      'featuredImage' => { 'url' => 'https://cdn.example/branca.jpg' },
      'images' => { 'nodes' => [] },
      'options' => [{ 'name' => 'Cor', 'optionValues' => [{ 'name' => 'Branca' }, { 'name' => 'Preta' }] },
                    { 'name' => 'Tamanho', 'optionValues' => [{ 'name' => 'P' }, { 'name' => 'GG' }] }],
      'variants' => { 'nodes' => [
        { 'id' => 'gid://shopify/ProductVariant/1', 'availableForSale' => true,
          'selectedOptions' => [{ 'name' => 'Cor', 'value' => 'Branca' }, { 'name' => 'Tamanho', 'value' => 'P' }],
          'price' => { 'amount' => '149.9' }, 'image' => { 'url' => 'https://cdn.example/branca.jpg' } }
      ] }
    }

    fake = Struct.new(:products_list) do
      def products(_refs) = products_list
      def kit_prices(_variant_id, max: 4) = { 1 => 149.9.to_d, 2 => 284.81.to_d, 3 => 418.22.to_d, 4 => 557.63.to_d }.first(max).to_h
      def configured? = true
      def endpoint = 'https://henrri.myshopify.com/api/2026-07/graphql.json'
      def token = 'public-token'
    end.new([product])

    Shopify::Storefront.stub :new, fake do
      get '/use1822/drop-01'
    end

    assert_response :success
    assert_match 'data-lp-kit', response.body
    assert_match 'Kit 4', response.body
    assert_no_match 'Kit 5', response.body
    assert_match 'R$ 557,63', response.body # Kit 4 com o desconto cotado na loja
    assert_match '−7%', response.body
    assert_match 'data-kit-prices', response.body
    assert_match 'data-lp-option="Cor"', response.body
  end

  test 'counts a chain break once per browser and returns the total' do
    post '/use1822/drop-01/break'
    assert_response :success
    assert_equal 1, response.parsed_body['count']

    post '/use1822/drop-01/break'
    assert_equal 1, response.parsed_body['count']
    assert_equal 1, @page.reload.chain_breaks_count
  end

  test 'a different browser adds to the count' do
    @page.update_columns(chain_breaks_count: 41)

    post '/use1822/drop-01/break'

    assert_equal 42, response.parsed_body['count']
  end

  test 'does not count chain breaks while previewing an inactive page' do
    @page.update!(active: false)
    Profile.find_or_create_by!(id: Profile::USER) { |p| p.name = 'User' }
    sign_in User.create!(name: 'U', email: "u-#{SecureRandom.hex(4)}@example.com", password: 'password123',
                         password_confirmation: 'password123', profile_id: Profile::USER, client: @client)

    post '/use1822/drop-01/break'

    assert_equal 0, @page.reload.chain_breaks_count
  end

  test 'renders the break badge with the current count and share text' do
    @page.update_columns(chain_breaks_count: 1234)

    get '/use1822/drop-01'

    assert_match 'data-breakbadge', response.body
    assert_match '1.234', response.body
    assert_match 'Ajude a romper essa corrente', response.body
    assert_match 'utm_source=compartilhar', response.body
    assert_match 'aria-expanded="false"', response.body
  end

  test 'credits Mewtda in the footer' do
    get '/use1822/drop-01'

    assert_match 'Desenvolvido por', response.body
    assert_match(/mewtda-logo-sm.*\.png/, response.body)
    assert_match 'href="https://www.mewtda.com.br"', response.body
  end
end
