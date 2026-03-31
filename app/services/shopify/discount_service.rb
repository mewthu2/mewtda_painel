module Shopify
  class DiscountService
    CASHBACK_TITLE_PATTERN = /Cashback\s+[\d,.]+%?\s*-\s*Pedido\s*#?(\d+)/i

    def initialize(client)
      @db_client = client
      @shopify = Shopify::Client.new(client)
    end

    # Busca todos os descontos paginados
    def fetch_all(limit: 250)
      discounts = []
      after_cursor = nil

      loop do
        result = fetch_page(limit: limit, after_cursor: after_cursor)
        discounts.concat(result[:discounts])

        break unless result[:has_next_page]
        after_cursor = result[:end_cursor]
      end

      discounts
    end

    # Busca uma página de descontos
    def fetch_page(limit: 50, after_cursor: nil)
      query = build_query(limit, after_cursor)
      data = @shopify.query(query)

      nodes_data = data.dig('codeDiscountNodes')
      raise StandardError, 'Dados de cupons não encontrados na resposta' unless nodes_data

      edges = nodes_data['edges'] || []
      page_info = nodes_data['pageInfo'] || {}

      discounts = edges.map { |edge| parse_discount(edge) }.compact

      {
        discounts: discounts,
        has_next_page: page_info['hasNextPage'] || false,
        end_cursor: page_info['endCursor']
      }
    end

    # Busca apenas descontos de cashback
    def fetch_cashback_discounts
      all_discounts = fetch_all
      all_discounts.select { |d| d[:title].to_s.match?(CASHBACK_TITLE_PATTERN) }
    end

    # Busca desconto de cashback pelo número do pedido
    # order_number pode ser "#2909", "2909", ou um Order
    def find_by_order(order_number)
      # Extrai apenas os dígitos do número do pedido
      if order_number.is_a?(Order)
        number = order_number.shopify_order_number.to_s.gsub(/\D/, '')
      else
        number = order_number.to_s.gsub(/\D/, '')
      end

      return nil if number.blank?

      # Busca usando query com filtro no título
      # Procura por "Cashback" E "#NUMERO" no título
      query = build_search_query("Cashback ##{number}")
      data = @shopify.query(query)

      nodes_data = data.dig('codeDiscountNodes')
      return nil unless nodes_data

      edges = nodes_data['edges'] || []
      discounts = edges.map { |edge| parse_discount(edge) }.compact

      # Filtra para garantir que o número do pedido está correto
      discounts.find do |d|
        title = d[:title].to_s
        title.match?(/cashback/i) && title.include?("##{number}")
      end
    end

    # Busca todos os descontos de cashback para um pedido específico
    def find_all_by_order(order_number)
      if order_number.is_a?(Order)
        number = order_number.shopify_order_number.to_s.gsub(/\D/, '')
      else
        number = order_number.to_s.gsub(/\D/, '')
      end

      return [] if number.blank?

      query = build_search_query("Cashback ##{number}")
      data = @shopify.query(query)

      nodes_data = data.dig('codeDiscountNodes')
      return [] unless nodes_data

      edges = nodes_data['edges'] || []
      discounts = edges.map { |edge| parse_discount(edge) }.compact

      discounts.select do |d|
        title = d[:title].to_s
        title.match?(/cashback/i) && title.include?("##{number}")
      end
    end

    # Busca um desconto específico por código
    def find_by_code(code)
      query = <<~GRAPHQL
        {
          codeDiscountNodeByCode(code: "#{code}") {
            id
            codeDiscount {
              __typename
              ... on DiscountCodeBasic {
                #{discount_fields}
              }
            }
          }
        }
      GRAPHQL

      data = @shopify.query(query)
      node = data.dig('codeDiscountNodeByCode')
      return nil unless node

      parse_discount({ 'node' => node })
    end

    # Busca descontos ativos (não expirados)
    def fetch_active
      fetch_all.select { |d| d[:is_active] && !d[:is_expired] }
    end

    # Busca descontos que vão expirar em X dias
    def fetch_expiring_in(days:)
      target_date = Date.current + days.days
      
      fetch_active.select do |d|
        next false unless d[:ends_at].present?
        
        expires_on = d[:ends_at].to_date
        expires_on >= Date.current && expires_on <= target_date
      end
    end

    private

    def build_query(limit, after_cursor)
      <<~GRAPHQL
        {
          codeDiscountNodes(first: #{limit}#{after_cursor ? ", after: \"#{after_cursor}\"" : ''}) {
            pageInfo {
              hasNextPage
              endCursor
            }
            edges {
              node {
                id
                codeDiscount {
                  __typename
                  ... on DiscountCodeBasic {
                    #{discount_fields}
                  }
                }
              }
            }
          }
        }
      GRAPHQL
    end

    def build_search_query(search_term)
      <<~GRAPHQL
        {
          codeDiscountNodes(first: 50, query: "title:*#{search_term}*") {
            pageInfo {
              hasNextPage
              endCursor
            }
            edges {
              node {
                id
                codeDiscount {
                  __typename
                  ... on DiscountCodeBasic {
                    #{discount_fields}
                  }
                }
              }
            }
          }
        }
      GRAPHQL
    end

    def discount_fields
      <<~FIELDS
        codes(first: 10) {
          nodes {
            code
          }
        }
        startsAt
        endsAt
        title
        summary
        usageLimit
        appliesOncePerCustomer
        combinesWith {
          orderDiscounts
          productDiscounts
          shippingDiscounts
        }
        customerGets {
          value {
            ... on DiscountPercentage {
              percentage
            }
            ... on DiscountAmount {
              amount {
                amount
                currencyCode
              }
            }
          }
          items {
            ... on AllDiscountItems {
              allItems
            }
          }
        }
        minimumRequirement {
          ... on DiscountMinimumQuantity {
            greaterThanOrEqualToQuantity
          }
          ... on DiscountMinimumSubtotal {
            greaterThanOrEqualToSubtotal {
              amount
              currencyCode
            }
          }
        }
        customerSelection {
          ... on DiscountCustomerAll {
            allCustomers
          }
        }
        createdAt
        updatedAt
        asyncUsageCount
        status
      FIELDS
    end

    def parse_discount(edge)
      return nil unless edge && edge['node'] && edge['node']['codeDiscount']

      discount_data = edge['node']['codeDiscount']
      return nil unless discount_data && discount_data['__typename'] == 'DiscountCodeBasic'

      codes = discount_data.dig('codes', 'nodes') || []
      return nil if codes.empty?

      main_code = codes.first
      return nil unless main_code && main_code['code']

      node_id = edge['node']['id']
      ends_at = discount_data['endsAt'] ? Time.parse(discount_data['endsAt']) : nil
      starts_at = discount_data['startsAt'] ? Time.parse(discount_data['startsAt']) : nil
      now = Time.current

      is_active = true
      is_expired = false

      if starts_at && starts_at > now
        is_active = false
      elsif ends_at && ends_at <= now
        is_active = false
        is_expired = true
      end

      # Extrai valor do desconto
      customer_gets = discount_data['customerGets']
      discount_value = nil
      discount_type = nil
      currency_code = 'BRL'

      if customer_gets && customer_gets['value']
        if customer_gets['value']['percentage']
          discount_value = customer_gets['value']['percentage']
          discount_type = 'percentage'
        elsif customer_gets['value']['amount']
          discount_value = customer_gets['value']['amount']['amount']
          currency_code = customer_gets['value']['amount']['currencyCode'] || 'BRL'
          discount_type = 'fixed_amount'
        end
      end

      {
        shopify_node_id: node_id,
        shopify_id: node_id.split('/').last,
        code: main_code['code'],
        title: discount_data['title'] || main_code['code'],
        summary: discount_data['summary'],
        is_active: is_active,
        is_expired: is_expired,
        status: discount_data['status'] || 'ACTIVE',
        starts_at: starts_at,
        ends_at: ends_at,
        discount_type: discount_type || 'percentage',
        discount_value: discount_value || 0,
        currency_code: currency_code,
        usage_limit: discount_data['usageLimit'],
        usage_count: discount_data['asyncUsageCount'] || 0,
        one_per_customer: discount_data['appliesOncePerCustomer'] || false,
        created_at: discount_data['createdAt'] ? Time.parse(discount_data['createdAt']) : nil,
        updated_at: discount_data['updatedAt'] ? Time.parse(discount_data['updatedAt']) : nil,
        raw_data: discount_data
      }
    end
  end
end
