class Order < ApplicationRecord
  enum kinds: [:shopify]

  belongs_to :customer, optional: true
  has_many :order_items
end