class ExchangeRequest < ApplicationRecord
  belongs_to :client
  has_many :exchange_request_items, dependent: :destroy

  enum status: { pending: 0, approved: 1, rejected: 2, completed: 3 }

  validates :shopify_order_id, :shopify_order_number, :customer_email, presence: true

  def troca_items
    exchange_request_items.select(&:troca?)
  end

  def troca_total
    troca_items.sum { |item| item.price.to_f * item.quantity.to_i }
  end
end
