module HomeHelper
  # Lê os arquivos direto de app/assets/images/admin/clients (qualquer
  # extensão) pra não precisar mexer em código toda vez que um logo de
  # cliente novo for adicionado/removido — só soltar o arquivo na pasta.
  def client_logo_assets
    dir = Rails.root.join('app', 'assets', 'images', 'admin', 'clients')
    Dir.glob(dir.join('*'))
       .select { |path| File.file?(path) }
       .sort
       .map { |path| "admin/clients/#{File.basename(path)}" }
  end

  # Imagens opcionais da landing (ex: print do painel): se o arquivo ainda
  # não foi colocado em app/assets/images, a view usa um fallback em vez de
  # quebrar o asset pipeline.
  def landing_image?(path)
    Rails.root.join('app', 'assets', 'images', path).file?
  end

  # Os 4 produtos da landing, na ordem das seções. Nomes são marca (não
  # traduzem); `anchor` é o id da seção na página.
  LANDING_PRODUCTS = [
    { key: 'crm',    name: 'CRM',         color: '#1d4ed8', icon: 'fa-solid fa-chart-line',              anchor: 'crm' },
    { key: 'trocas', name: 'Troca Fácil', color: '#16a34a', icon: 'fa-solid fa-arrow-right-arrow-left', anchor: 'trocas' },
    { key: 'new',    name: 'New',         color: '#fc7107', icon: 'fa-brands fa-shopify',                anchor: 'sites' },
    { key: 'app',    name: 'App',         color: '#7c3aed', icon: 'fa-solid fa-mobile-screen',          anchor: 'apps' }
  ].freeze

  def landing_products
    LANDING_PRODUCTS
  end

  def landing_product(key)
    LANDING_PRODUCTS.find { |product| product[:key] == key }
  end
end
