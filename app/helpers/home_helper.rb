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

  # Site de cada cliente, pelo nome do arquivo do logo (sem extensão).
  # Logo sem entrada aqui aparece na faixa, só que sem link.
  CLIENT_SITES = {
    'allie'                                        => 'https://alliebrand.com.br/',
    'brysa'                                        => 'https://brysabysa.com.br/',
    'DUNAS-BRANCO'                                 => 'https://dunasdn.com/',
    'email-2024'                                   => 'https://lojaoneway.com/',
    'henrri_negativo'                              => 'https://henrri.com.br/',
    'kace'                                         => 'https://www.kacewear.com.br/',
    'logo'                                         => 'https://www.usezaos.com.br/',
    'LOGO_BRANCA'                                  => 'https://fernandafarah.com.br/',
    'logosite1'                                    => 'https://chasebrasil.com/',
    'lyss'                                         => 'https://lyssoficial.com.br/',
    'patoge___798a6e88db039123eb791da15c900bdf'    => 'https://www.loja.patoge.com.br/',
    'priscilatorres'                               => 'https://priscilatorresdesign.com.br/',
    'TOP_ARARA_5'                                  => 'https://domaniactive.com/',
    'unnamed_6f13f59e-b3a2-4319-89aa-b17039a21da1' => 'https://gethallie.com/',
    'velvy'                                        => 'https://velvycoffee.com.br/',
    'VORR_dog_dourado_texto_preto_transparente'    => 'https://vorr.com.br/',
    'yousports'                                    => 'https://yousports.com.br/'
  }.freeze

  def client_site(logo_path)
    CLIENT_SITES[File.basename(logo_path, '.*')]
  end

  # Lojas criadas pela Mewtda que aparecem na seção "Sua Loja" (03), com
  # os prints de desktop (1600×900) e celular (780×1688) da home de cada uma.
  SITE_CASES = [
    { key: 'fernandafarah', name: 'Fernanda Farah', url: 'https://fernandafarah.com.br/',
      desktop: 'landing/site-desktop.jpg', mobile: 'landing/site-mobile.jpg' },
    { key: 'allie', name: 'Allie', url: 'https://alliebrand.com.br/',
      desktop: 'landing/site-allie-desktop.jpg', mobile: 'landing/site-allie-mobile.jpg' },
    { key: 'patoge', name: 'Patogê', url: 'https://www.loja.patoge.com.br/',
      desktop: 'landing/site-patoge-desktop.jpg', mobile: 'landing/site-patoge-mobile.jpg' },
    { key: 'vorr', name: 'Vörr', url: 'https://vorr.com.br/',
      desktop: 'landing/site-vorr-desktop.jpg', mobile: 'landing/site-vorr-mobile.jpg' }
  ].map { |c| c.merge(host: URI(c[:url]).host.delete_prefix('www.')).freeze }.freeze

  def site_cases
    SITE_CASES
  end

  # Imagens opcionais da landing (ex: print do painel): se o arquivo ainda
  # não foi colocado em app/assets/images, a view usa um fallback em vez de
  # quebrar o asset pipeline.
  def landing_image?(path)
    Rails.root.join('app', 'assets', 'images', path).file?
  end

  # Os 4 produtos da landing, na ordem das seções. Nomes são marca (não
  # traduzem); `anchor` é o id da seção na página. `logo` (opcional)
  # troca o wordmark em CSS pela imagem da marca própria.
  LANDING_PRODUCTS = [
    { key: 'crm',    name: 'MeuCRM',      color: '#0b72e7', icon: 'fa-solid fa-chart-line',              anchor: 'crm',
      logo: 'landing/meu-crm-logo.png' },
    { key: 'trocas', name: 'Quero Trocar', color: '#04432f', icon: 'fa-solid fa-arrow-right-arrow-left', anchor: 'trocas',
      logo: 'landing/quero-trocar-logo.png' },
    { key: 'new',    name: 'Sua Loja',    color: '#1a7fdc', icon: 'fa-brands fa-shopify',                anchor: 'sites',
      logo: 'landing/sua-loja-logo.png' },
    { key: 'app',    name: 'App',         color: '#1a7fdc', icon: 'fa-solid fa-mobile-screen',          anchor: 'apps',
      logo: 'landing/app-logo.png' }
  ].freeze

  def landing_products
    LANDING_PRODUCTS
  end

  def landing_product(key)
    LANDING_PRODUCTS.find { |product| product[:key] == key }
  end
end
