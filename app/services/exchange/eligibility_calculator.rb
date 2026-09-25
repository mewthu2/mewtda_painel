module Exchange
  class EligibilityCalculator
    def initialize(config)
      @config = config
    end

    def call(order)
      return :cancelled if order[:cancelled]
      return :not_fulfilled if order[:fulfilled_at].blank?

      days_since_fulfillment = (Date.current - order[:fulfilled_at].to_date).to_i
      days_since_fulfillment <= @config.return_window_days ? :return_and_exchange : :exchange_only
    end
  end
end
