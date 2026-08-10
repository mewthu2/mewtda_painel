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
        orders_count: orders_count,
        avg_ticket: avg_ticket,
        conversion_rate: conversion_rate,
        ad_cost: ad_cost,
        ad_cost_available: ad_cost_available?,
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

    def orders_scope
      scope = Order.not_cancelled.where(client_id: client.id, shopify_creation_date: period)
      scope = scope.where('tags ILIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(tag)}%") if tag.present?
      scope
    end

    def revenue
      orders_scope.sum(:total_price)
    end

    def gross_sales
      orders_scope.sum(:subtotal_price)
    end

    def discounts
      orders_scope.sum(:total_discounts)
    end

    def orders_count
      orders_scope.count
    end

    def avg_ticket
      return nil if orders_count.zero?

      revenue / orders_count
    end

    def unique_sessions
      ShopifyEvent
        .where(client_id: client.id, kind: 'page_viewed', created_at: period)
        .distinct
        .count(:session_id)
    end

    def conversion_rate
      return nil if unique_sessions.zero?

      (orders_count.to_f / unique_sessions * 100).round(2)
    end

    def configured_platforms
      platforms = []
      platforms << 'google_ads' if client.google_ads_configured?
      platforms << 'meta' if client.meta_configured?
      platforms
    end

    def ad_cost_snapshots
      AdCostSnapshot.where(client_id: client.id, year: year, month: month)
    end

    def ad_cost_available?
      return false if configured_platforms.empty?

      configured_platforms.all? { |platform| ad_cost_snapshots.exists?(platform: platform) }
    end

    def ad_cost
      ad_cost_snapshots.where(platform: configured_platforms).sum(:cost)
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
