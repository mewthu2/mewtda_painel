class CreateCashbackDiscountJob < ApplicationJob
  queue_as :default

  def perform(order_id)
    order = Order.includes(:customer).find(order_id)

    result = Shopify::CreateCashbackDiscount.call(order:)

    CustomerNotificationJob.perform_now(
      order.id,
      result[:coupon_code],
      :purchase
    )
  end
end
