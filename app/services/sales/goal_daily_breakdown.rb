module Sales
  # Série diária de cada métrica usada nas Metas do Mês, no mesmo formato do
  # gráfico "Vendas por dia" — permite ver dia a dia se o ritmo está batendo
  # com a meta, em vez de só o total acumulado do mês.
  class GoalDailyBreakdown
    def initialize(client:, year:, month:, tag: nil)
      @client = client
      @year = year
      @month = month
      @tag = tag
    end

    def call
      {
        days: days,
        days_in_month: month_end.day,
        revenue_by_day: revenue_by_day,
        avg_ticket_by_day: avg_ticket_by_day,
        conversion_rate_by_day: conversion_rate_by_day,
        roas_by_day: roas_by_day,
        cac_by_day: cac_by_day,
        tagged_revenue_by_day: tagged_revenue_by_day,
        orders_count_by_day: orders_count_by_day,
        total_revenue_by_day: total_revenue_by_day,
        sessions_by_day: sessions_series('page_viewed'),
        checkout_completed_count_by_day: sessions_series('checkout_completed')
      }
    end

    private

    attr_reader :client, :year, :month, :tag

    def month_start
      Date.new(year, month, 1)
    end

    def month_end
      month_start.end_of_month
    end

    def last_day
      [month_end, Date.current].min
    end

    def days
      (month_start.day..last_day.day).to_a
    end

    def period
      month_start.beginning_of_day..month_end.end_of_day
    end

    def orders_scope
      Order.not_cancelled.where(client_id: client.id, shopify_creation_date: period)
    end

    def order_totals_by_day
      local_date = Sales::LocalDate.sql('shopify_creation_date')

      @order_totals_by_day ||= orders_scope
                               .group(Arel.sql(local_date))
                               .pluck(Arel.sql(
                                        "#{local_date}, SUM(subtotal_price), " \
                                        'SUM(total_shipping_price), SUM(total_price), COUNT(*)'
                                      ))
                               .each_with_object({}) do |(date, net, shipping, total, count), memo|
        memo[date.day] = { net: net.to_f, shipping: shipping.to_f, total: total.to_f, count: count }
      end
    end

    # Faturamento (Bruto − Descontos) por dia — mesma base usada na meta de
    # Faturamento (Sales::MonthlyMetrics compara a meta contra net_of_discounts).
    def revenue_by_day
      days.map { |d| order_totals_by_day.dig(d, :net) || 0.0 }
    end

    def avg_ticket_by_day
      days.map do |d|
        entry = order_totals_by_day[d]
        entry && entry[:count].positive? ? (entry[:total] / entry[:count]).round(2) : nil
      end
    end

    def orders_count_by_day
      days.map { |d| order_totals_by_day.dig(d, :count) || 0 }
    end

    # Faturamento total do dia (líquido + frete) — mesma base do card
    # "Faturamento" no topo do dashboard, usada no modal de detalhe do dia.
    def total_revenue_by_day
      days.map do |d|
        entry = order_totals_by_day[d]
        entry ? (entry[:net] + entry[:shipping]).round(2) : 0.0
      end
    end

    def tagged_orders_scope
      return orders_scope.none if tag.blank?

      orders_scope.where('tags ILIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(tag)}%")
    end

    def tagged_totals_by_day
      local_date = Sales::LocalDate.sql('shopify_creation_date')

      @tagged_totals_by_day ||= tagged_orders_scope
                                .group(Arel.sql(local_date))
                                .pluck(Arel.sql("#{local_date}, SUM(subtotal_price)"))
                                .each_with_object({}) { |(date, net), memo| memo[date.day] = net.to_f }
    end

    def tagged_revenue_by_day
      days.map { |d| tagged_totals_by_day[d] || 0.0 }
    end

    def sessions_by_day(kind)
      ShopifyEvent
        .where(client_id: client.id, kind: kind, created_at: period)
        .pluck(Arel.sql(Sales::LocalDate.sql('created_at')), :session_id)
        .group_by { |date, _| date.day }
        .transform_values { |rows| rows.map { |_, sid| sid }.uniq.size }
    end

    def page_viewed_by_day
      @page_viewed_by_day ||= sessions_by_day('page_viewed')
    end

    def checkout_completed_by_day
      @checkout_completed_by_day ||= sessions_by_day('checkout_completed')
    end

    def sessions_series(kind)
      totals = kind == 'page_viewed' ? page_viewed_by_day : checkout_completed_by_day
      days.map { |d| totals[d] || 0 }
    end

    # Pedidos reais do dia (não o evento de pixel "checkout_completed", que
    # perde conversões por ad blocker/timing) / acessos do dia.
    def conversion_rate_by_day
      days.map do |d|
        pv = page_viewed_by_day[d] || 0
        next nil if pv.zero?

        orders = order_totals_by_day.dig(d, :count) || 0
        (orders.to_f / pv * 100).round(2)
      end
    end

    # Distribui cada custo de anúncio igualmente pelos dias que ele cobre —
    # os custos são cadastrados por período (início/fim), não por dia.
    def ad_cost_by_day
      @ad_cost_by_day ||= begin
        totals = Hash.new(0.0)
        client.ad_costs.overlapping(month_start, month_end).find_each do |cost|
          cost_days = (cost.start_date..cost.end_date).to_a
          next if cost_days.empty?

          per_day = cost.amount.to_f / cost_days.size
          cost_days.each do |d|
            totals[d.day] += per_day if d.year == year && d.month == month
          end
        end
        totals
      end
    end

    def roas_by_day
      days.map do |d|
        cost = ad_cost_by_day[d] || 0.0
        next nil if cost.zero?

        entry = order_totals_by_day[d]
        revenue = entry ? entry[:net] + entry[:shipping] : 0.0
        (revenue / cost).round(2)
      end
    end

    def new_customers_by_day
      @new_customers_by_day ||= Customer
                                .joins(:orders)
                                .where(orders: { client_id: client.id, cancelled_at: nil })
                                .group('customers.id')
                                .having('MIN(orders.shopify_creation_date) BETWEEN ? AND ?', period.first, period.last)
                                .pluck(Arel.sql('MIN(orders.shopify_creation_date)'))
                                .group_by { |date| date.in_time_zone(Sales::LocalDate::TIME_ZONE).to_date.day }
                                .transform_values(&:size)
    end

    def cac_by_day
      days.map do |d|
        cost = ad_cost_by_day[d] || 0.0
        next nil if cost.zero?

        customers = new_customers_by_day[d] || 0
        next nil if customers.zero?

        (cost / customers).round(2)
      end
    end
  end
end
