module LandingPages
  # Atualiza os produtos guardados na landing page (ver CachedStorefront) com o
  # que está na Shopify agora: os handles da página e tudo que já estava
  # guardado (ex.: produto que o template busca pelo ID). Produto ou variante
  # que sumiu da loja sai do cache. Se a Shopify falhar no meio, nada muda.
  class SyncProducts
    Result = Struct.new(:ok, :products_count, :error, keyword_init: true)

    def initialize(landing_page, storefront = Shopify::Storefront.new(landing_page.client))
      @page = landing_page
      @storefront = storefront
    end

    def call
      return Result.new(ok: false, error: 'Token da Storefront API não configurado para este cliente.') unless @storefront.configured?

      cache = @page.storefront_cache
      refs = (@page.product_handles + cache.fetch('products', {}).keys).uniq
      products = refs.each_with_object({}) do |ref, found|
        product = @storefront.fetch_product!(ref)
        found[ref] = product if product
      end

      variant_ids = products.values.flat_map { |p| Array(p.dig('variants', 'nodes')).map { |v| v['id'] } }
      kit_prices = cache.fetch('kit_prices', {}).slice(*variant_ids).each_with_object({}) do |(variant_id, old), quoted|
        prices = @storefront.fetch_kit_prices!(variant_id, max: old.size)
        quoted[variant_id] = prices.transform_values(&:to_s) if prices
      end

      @page.update_columns(storefront_cache: { 'products' => products, 'kit_prices' => kit_prices }.as_json,
                           storefront_synced_at: Time.current)
      Result.new(ok: true, products_count: products.size)
    rescue Shopify::Storefront::Error => e
      Rails.logger.error("[LandingPages::SyncProducts] landing page #{@page.id}: #{e.message}")
      Result.new(ok: false, error: "A Shopify não respondeu (#{e.message}). Nada foi alterado, tente de novo.")
    end
  end
end
