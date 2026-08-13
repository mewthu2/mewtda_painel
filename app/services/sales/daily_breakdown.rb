module Sales
  class DailyBreakdown
    def initialize(client:, year:, month:)
      @client = client
      @year = year
      @month = month
    end

    def call
      revenue_by_day = days.map { |day| totals_by_day.dig(day, :revenue) || 0 }
      orders_by_day = days.map { |day| totals_by_day.dig(day, :orders) || 0 }
      avg_ticket_by_day = revenue_by_day.zip(orders_by_day).map do |revenue, orders|
        orders.zero? ? nil : revenue / orders
      end

      {
        days: days,
        revenue_by_day: revenue_by_day,
        orders_by_day: orders_by_day,
        avg_ticket_by_day: avg_ticket_by_day,
        revenue_total: revenue_total,
        orders_total: orders_total,
        avg_ticket_total: orders_total.zero? ? nil : revenue_total / orders_total,
        has_data: orders_total.positive?
      }
    end

    private

    attr_reader :client, :year, :month

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

    def totals_by_day
      @totals_by_day ||= orders_scope
                          .group("DATE(shopify_creation_date)")
                          .pluck(Arel.sql("DATE(shopify_creation_date), SUM(total_price), COUNT(*)"))
                          .each_with_object({}) do |(date, revenue, orders), memo|
                            memo[date.day] = { revenue: revenue, orders: orders }
                          end
    end

    def revenue_total
      orders_scope.sum(:total_price)
    end

    def orders_total
      orders_scope.count
    end
  end
end
