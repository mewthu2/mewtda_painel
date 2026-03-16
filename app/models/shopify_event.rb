class ShopifyEvent < ApplicationRecord
  belongs_to :client
  belongs_to :integration_user

  validates :kind, presence: true
  validates :session_id, presence: true

  scope :checkout_completed, -> { where(kind: "checkout_completed") }
  scope :added_to_cart, -> { where(kind: "product_added_to_cart") }
  scope :product_viewed, -> { where(kind: "product_viewed") }
  scope :page_viewed, -> { where(kind: "page_viewed") }
end