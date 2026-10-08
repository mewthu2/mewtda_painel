module LandingPages
  # Produtos (e cotações de kit) da Storefront API guardados na própria landing
  # page, na coluna storefront_cache, pra página abrir sem consultar a Shopify.
  # Tem a mesma interface do Shopify::Storefront que os templates usam.
  #
  # O que ainda não está guardado é buscado ao vivo na primeira visita e fica
  # guardado; o SyncProducts atualiza tudo (todo dia de madrugada e pelo botão
  # "Sincronizar produtos" no painel).
  class CachedStorefront
    delegate :configured?, :endpoint, :token, to: :@live

    def initialize(landing_page, live = Shopify::Storefront.new(landing_page.client))
      @page = landing_page
      @live = live
    end

    def products(refs)
      Array(refs).filter_map { |ref| product(ref) }
    end

    def product(ref)
      return nil if ref.blank?

      cached('products', ref) { @live.product(ref) }
    end

    # { 1 => 69.9, 2 => 132.82, ... } (BigDecimal), como Shopify::Storefront#kit_prices.
    def kit_prices(variant_id, max: 4)
      return {} if variant_id.blank?

      stored = @page.storefront_cache.dig('kit_prices', variant_id)
      prices = if stored && stored.size >= max
                 stored
               else
                 live = @live.kit_prices(variant_id, max: max).presence
                 live && remember('kit_prices', variant_id, live.transform_values(&:to_s))
               end
      prices.to_h { |quantity, amount| [quantity.to_i, amount.to_d] }.select { |quantity, _| quantity <= max }
    end

    private

    def cached(section, key)
      stored = @page.storefront_cache.dig(section, key)
      return stored if stored

      value = yield
      value && remember(section, key, value) # nil (falhou ou não existe) não guarda: tenta de novo na próxima
    end

    # Grava só a chave nova, num UPDATE atômico: duas visitas ao mesmo tempo
    # não apagam o que a outra guardou.
    def remember(section, key, value)
      value = value.as_json
      LandingPage.where(id: @page.id).update_all([
        "storefront_cache = storefront_cache || jsonb_build_object(:section::text, " \
        "COALESCE(storefront_cache -> :section, '{}'::jsonb) || jsonb_build_object(:key::text, :value::jsonb))",
        { section: section, key: key, value: value.to_json }
      ])
      (@page.storefront_cache[section] ||= {})[key] = value
      @page.clear_attribute_changes([:storefront_cache])
      value
    end
  end
end
