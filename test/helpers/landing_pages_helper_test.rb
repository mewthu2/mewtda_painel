require 'test_helper'

class LandingPagesHelperTest < ActionView::TestCase
  def product(variant_images:)
    {
      'options' => [{ 'name' => 'Color', 'optionValues' => [{ 'name' => 'Branco' }, { 'name' => 'Preto' }] }],
      'images' => { 'nodes' => [{ 'url' => 'https://cdn/1.jpg' }, { 'url' => 'https://cdn/2.jpg' }, { 'url' => 'https://cdn/3.jpg' }] },
      'variants' => { 'nodes' => %w[Branco Preto].each_with_index.map do |cor, i|
        { 'id' => "v#{i}", 'availableForSale' => true, 'price' => { 'amount' => '69.9' },
          'selectedOptions' => [{ 'name' => 'Color', 'value' => cor }], 'image' => { 'url' => variant_images[i] } }
      end }
    }
  end

  test 'uses each variant image when colors have distinct photos' do
    p = product(variant_images: %w[https://cdn/3.jpg https://cdn/2.jpg])
    assert_equal({ 'Branco' => 'https://cdn/3.jpg', 'Preto' => 'https://cdn/2.jpg' }, lp_option_images(p))
    assert_equal %w[https://cdn/3.jpg https://cdn/2.jpg], lp_gallery_images(p).map { |i| i['url'] }
  end

  test 'falls back to product photos in option order when every color shares the same photo' do
    p = product(variant_images: %w[https://cdn/1.jpg https://cdn/1.jpg])
    assert_equal({ 'Branco' => 'https://cdn/1.jpg', 'Preto' => 'https://cdn/2.jpg' }, lp_option_images(p))
    assert_equal %w[https://cdn/1.jpg https://cdn/2.jpg], lp_gallery_images(p).map { |i| i['url'] }
    assert_includes lp_variants_json(p), 'https://cdn/2.jpg?width=300'
  end

  test 'shows option names in Portuguese' do
    assert_equal 'Cor', lp_option_label('Color')
    assert_equal 'Tamanho', lp_option_label('Size')
    assert_equal 'Estampa', lp_option_label('Estampa')
  end

  def color_product(id, color, image)
    {
      'id' => "gid://shopify/Product/#{id}", 'title' => "Camiseta Independência #{color}", 'availableForSale' => true,
      'featuredImage' => { 'url' => image }, 'images' => { 'nodes' => [{ 'url' => image }] },
      'options' => [{ 'name' => 'Color', 'optionValues' => [{ 'name' => color }] },
                    { 'name' => 'Size', 'optionValues' => %w[P M].map { |t| { 'name' => t } } }],
      'variants' => { 'nodes' => %w[P M].map do |t|
        { 'id' => "gid://shopify/ProductVariant/#{id}#{t}", 'availableForSale' => true, 'price' => { 'amount' => '69.9' },
          'selectedOptions' => [{ 'name' => 'Color', 'value' => color }, { 'name' => 'Size', 'value' => t }],
          'image' => { 'url' => image } }
      end }
    }
  end

  test 'merges one product per color into a single kit product' do
    merged = lp_merge_products([color_product(1, 'Branco', 'https://cdn/b.jpg'), color_product(2, 'Preto', 'https://cdn/p.jpg')])

    assert_equal 'Camiseta Independência', merged['title']
    assert_equal %w[Branco Preto], merged['options'].first['optionValues'].map { |v| v['name'] }
    assert_equal %w[P M], merged['options'].last['optionValues'].map { |v| v['name'] }
    assert_equal 4, merged['variants']['nodes'].size
    assert_equal %w[https://cdn/b.jpg https://cdn/p.jpg], lp_gallery_images(merged).map { |i| i['url'] }
  end

  test 'does not merge products with different options' do
    other = color_product(3, 'Preto', 'https://cdn/x.jpg')
    other['options'] = [{ 'name' => 'Estampa', 'optionValues' => [{ 'name' => 'A' }] }]

    assert_nil lp_merge_products([color_product(1, 'Branco', 'https://cdn/b.jpg'), other])
  end
end
