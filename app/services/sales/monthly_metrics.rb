module Sales
  class MonthlyMetrics
    def initialize(client:, year:, month:, tag: nil)
      @client = client
      @year = year
      @month = month
      @tag = tag
    end

    def call
      {
        revenue: revenue,
        gross_sales: gross_sales,
        discounts: discounts,
        net_of_discounts: net_of_discounts,
        reversals: reversals,
        net_sales: net_sales,
        shipping: shipping,
        orders_count: orders_count,
        avg_ticket: avg_ticket,
        ad_cost: ad_cost,
        ad_cost_available: ad_cost_available?,
        ad_cost_by_platform: ad_cost_by_platform,
        configured_platforms: configured_platforms,
        roas: roas,
        new_customers_count: new_customers_count,
        cac: cac
      }
    end

    private

    attr_reader :client, :year, :month, :tag

    def period
      start = Time.zone.local(year, month, 1).beginning_of_day
      start..start.end_of_month
    end

    # Pedidos NÃO cancelados: usado pra contagem de pedidos e ticket médio (volume real).
    def orders_scope
      scope = Order.not_cancelled.where(client_id: client.id, shopify_creation_date: period)
      scope = scope.where('tags ILIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(tag)}%") if tag.present?
      scope
    end

    # TODOS os pedidos criados no período, incluindo cancelados: o relatório "Total
    # Sales" do Shopify conta o valor original de todo pedido no Bruto, mesmo cancelado,
    # e reverte esse valor separadamente (ver #reversals) — não simplesmente ignora.
    def all_orders_scope
      scope = Order.where(client_id: client.id, shopify_creation_date: period)
      scope = scope.where('tags ILIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(tag)}%") if tag.present?
      scope
    end

    # Fórmula "Total Sales" do Shopify: net sales + frete (BR não usa Shopify Tax).
    def revenue
      net_sales + shipping
    end

    # subtotal_price do Shopify já vem líquido de descontos (não é o "bruto" de fato).
    # Reconstituímos o valor bruto somando o desconto de volta, pra a UI conseguir
    # mostrar o caminho completo: Bruto - Descontos = Líquido de produtos - Reembolsos = Líquido.
    def gross_sales
      net_of_discounts + discounts
    end

    def net_of_discounts
      all_orders_scope.sum(:subtotal_price)
    end

    def discounts
      all_orders_scope.sum(:total_discounts)
    end

    # Duas fontes de reversão, cada uma pela data em que o evento aconteceu (não a
    # data de criação do pedido) — mesmo critério do "Sales reversals" do Shopify:
    #   1. Reembolsos reais (dinheiro devolvido) processados no período.
    #   2. Pedidos cancelados no período que nunca chegaram a ser cobrados (sem
    #      transação de reembolso, porque não tinha o que devolver) — sem isso, o
    #      valor deles ficaria contado no Bruto sem nunca ser revertido.
    # Não dá pra atribuir reversão a uma tag específica, então com filtro de tag ativo
    # essa dedução é ignorada (mesma limitação já existente em ROAS/CAC).
    def reversals
      return 0 if tag.present?

      refund_reversals + cancelled_without_refund_reversals
    end

    def refund_reversals
      client.refunds.where(processed_at: period).sum(:amount)
    end

    def cancelled_without_refund_reversals
      Order
        .where(client_id: client.id, cancelled_at: period)
        .where.not(id: client.refunds.where.not(order_id: nil).select(:order_id))
        .sum(:subtotal_price)
    end

    def net_sales
      net_of_discounts - reversals
    end

    def shipping
      all_orders_scope.sum(:total_shipping_price)
    end

    def orders_count
      orders_scope.count
    end

    # Baseado no valor original de cada pedido (não no Faturamento ajustado por
    # reembolsos de outros períodos), pra representar o ticket de fato daquele pedido.
    def avg_ticket
      return nil if orders_count.zero?

      orders_scope.sum(:total_price) / orders_count
    end

    def configured_platforms
      client.ad_costs.distinct.pluck(:platform)
    end

    def ad_costs_in_period
      client.ad_costs.overlapping(period.first.to_date, period.last.to_date)
    end

    def ad_cost_available?
      ad_costs_in_period.exists?
    end

    def ad_cost
      ad_costs_in_period.sum(:amount)
    end

    def ad_cost_by_platform
      ad_costs_in_period.group(:platform).sum(:amount)
    end

    def roas
      return nil unless ad_cost_available?
      return nil if ad_cost.zero?

      (revenue / ad_cost).round(2)
    end

    def new_customers_count
      Customer
        .joins(:orders)
        .where(orders: { client_id: client.id, cancelled_at: nil })
        .group('customers.id')
        .having('MIN(orders.shopify_creation_date) BETWEEN ? AND ?', period.first, period.last)
        .count
        .length
    end

    def cac
      return nil unless ad_cost_available?
      return nil if new_customers_count.zero?

      (ad_cost / new_customers_count).round(2)
    end
  end
end
