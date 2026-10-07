module LandingPagesHelper
  def lp_money(amount)
    number_to_currency(amount.to_d, unit: 'R$', separator: ',', delimiter: '.', format: '%u %n')
  end

  # A CDN da Shopify redimensiona pela query string ?width=.
  def lp_image_url(url, width)
    return nil if url.blank?

    "#{url}#{url.include?('?') ? '&' : '?'}width=#{width}"
  end

  # Opções que o comprador precisa escolher (a Shopify cria "Title / Default
  # Title" pra produto sem variação — essa não aparece).
  def lp_product_options(product)
    Array(product['options']).reject do |option|
      values = Array(option['optionValues']).map { |v| v['name'] }
      values.size <= 1 && values.first.to_s.match?(/\ADefault Title\z/i)
    end
  end

  OPTION_LABELS = { 'color' => 'Cor', 'colour' => 'Cor', 'size' => 'Tamanho', 'tamanho' => 'Tamanho', 'cor' => 'Cor' }.freeze

  # Nome da opção pra exibir (a loja pode estar com as opções em inglês).
  def lp_option_label(name)
    OPTION_LABELS.fetch(name.to_s.strip.downcase, name)
  end

  def lp_variants_json(product)
    images = lp_option_images(product)
    first_option = lp_product_options(product).first&.dig('name')

    Array(product.dig('variants', 'nodes')).map do |variant|
      options = Array(variant['selectedOptions']).to_h { |o| [o['name'], o['value']] }
      image = images[options[first_option]] || variant.dig('image', 'url')
      {
        id: variant['id'],
        available: variant['availableForSale'],
        price: variant.dig('price', 'amount'),
        options: options,
        image: lp_image_url(image, 300)
      }
    end.to_json
  end

  # Uma imagem por valor da primeira opção (ex.: uma por cor). Usa a imagem da
  # variante; se a loja deixou todas as cores com a mesma foto, cai pras fotos
  # do produto na ordem das opções (1ª cor → 1ª foto, 2ª cor → 2ª foto...).
  def lp_option_images(product)
    option = lp_product_options(product).first
    return {} unless option

    values = Array(option['optionValues']).map { |v| v['name'] }
    variants = Array(product.dig('variants', 'nodes'))
    from_variants = values.to_h do |value|
      variant = variants.find do |v|
        v['image'] && Array(v['selectedOptions']).any? { |o| o['name'] == option['name'] && o['value'] == value }
      end
      [value, variant&.dig('image', 'url')]
    end

    return from_variants if from_variants.values.compact.uniq.size == values.size

    product_images = Array(product.dig('images', 'nodes')).map { |i| i['url'] }
    return from_variants if product_images.size < values.size

    values.each_with_index.to_h { |value, i| [value, product_images[i]] }
  end

  # Junta produtos com as mesmas opções (ex.: "Camiseta Branco" e "Camiseta
  # Preto", ambos com Color + Size) num produto só pro kit: a cor escolhe o
  # produto e o tamanho a variante; no checkout cada peça vai pelo seu produto.
  # Retorna nil se as opções não baterem (aí cada produto tem seu kit).
  def lp_merge_products(products)
    products = Array(products)
    return products.first if products.size == 1

    option_names = products.map { |p| lp_product_options(p).map { |o| o['name'] } }
    return nil if products.empty? || option_names.map(&:sort).uniq.size != 1

    options = option_names.first.map do |name|
      values = products.flat_map { |p| Array(p['options']).find { |o| o['name'] == name }&.dig('optionValues').to_a }
      { 'name' => name, 'optionValues' => values.uniq { |v| v['name'] } }
    end

    {
      'id' => products.map { |p| p['id'] }.join(','),
      'title' => lp_common_title(products.map { |p| p['title'].to_s }),
      'availableForSale' => products.any? { |p| p['availableForSale'] },
      'featuredImage' => products.first['featuredImage'],
      'images' => { 'nodes' => products.flat_map { |p| Array(p.dig('images', 'nodes')) } },
      'options' => options,
      'variants' => { 'nodes' => products.flat_map { |p| Array(p.dig('variants', 'nodes')) } }
    }
  end

  # "Camiseta X Branco" + "Camiseta X Preto" => "Camiseta X".
  def lp_common_title(titles)
    words = titles.map(&:split)
    common = words.first.take_while.with_index { |word, i| words.all? { |w| w[i] == word } }
    common.join(' ').sub(/[\s\-–—·|]+\z/, '').presence || titles.first
  end

  def lp_first_available_variant_id(product)
    variants = Array(product.dig('variants', 'nodes'))
    (variants.find { |v| v['availableForSale'] } || variants.first)&.dig('id')
  end

  # Percentual de desconto do kit (0 se não houver).
  def lp_kit_discount_percent(kit_price, unit_price, quantity)
    return 0 unless kit_price && unit_price&.positive?

    full = unit_price * quantity
    kit_price < full ? ((1 - (kit_price / full)) * 100).round : 0
  end

  def lp_min_price(product)
    Array(product.dig('variants', 'nodes')).map { |v| v.dig('price', 'amount').to_d }.min
  end

  def lp_compare_at_price(product)
    Array(product.dig('variants', 'nodes')).filter_map { |v| v.dig('compareAtPrice', 'amount')&.to_d }.max
  end

  # Imagens pra galeria: uma por cor (ver lp_option_images); sem cores
  # distintas, as primeiras fotos do produto.
  def lp_gallery_images(product, limit: 2)
    all = Array(product.dig('images', 'nodes'))
    urls = lp_option_images(product).values.compact.uniq
    urls = all.map { |i| i['url'] } if urls.size < 2
    urls.first(limit).map { |url| all.find { |i| i['url'] == url } || { 'url' => url } }
  end
end
