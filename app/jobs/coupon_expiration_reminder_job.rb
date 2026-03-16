class CouponExpirationReminderJob < ApplicationJob
  queue_as :default

  def perform
    Discount.where(
      ends_at: 2.days.from_now.beginning_of_day..2.days.from_now.end_of_day
    ).find_each do |discount|

      order = Order.find_by(shopify_order_number: discount.title[/#\d+/])

      next unless order

      CustomerNotificationJob.perform_later(
        order.id,
        discount.code,
        :expiring
      )
    end
  end
end