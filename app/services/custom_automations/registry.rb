module CustomAutomations
  # Automações feitas sob medida pra um cliente. Cada entrada diz pra quais
  # clientes ela aparece — o match é pelo nome normalizado (sem acento, espaço
  # ou hífen), então "Fernanda Farah", "fernanda-farah" e "FernandaFarah" batem.
  module Registry
    AUTOMATIONS = {
      'fernanda_farah_transfer_note' => {
        title: 'Nota de transferência mensal (matriz → e-commerce)',
        description: 'Lê os pedidos do período na Shopify, monta uma NF de transferência (CFOP 5152) no Tiny da ' \
                     'matriz em nome da filial do e-commerce, gera a planilha de conferência e só emite depois ' \
                     'da aprovação.',
        icon: 'fa-solid fa-file-invoice',
        client_keys: %w[fernandafarah]
      }
    }.freeze

    module_function

    def kinds
      AUTOMATIONS.keys
    end

    def find(kind)
      AUTOMATIONS[kind.to_s]
    end

    def for_client(client)
      return {} if client.nil?

      key = normalize(client.name)
      AUTOMATIONS.select { |_kind, config| config[:client_keys].include?(key) }
    end

    def available?(client, kind)
      for_client(client).key?(kind.to_s)
    end

    def normalize(name)
      name.to_s.parameterize.delete('-')
    end
  end
end
