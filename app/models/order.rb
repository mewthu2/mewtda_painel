class Order < ApplicationRecord
  belongs_to :customer, optional: true
  belongs_to :client
  belongs_to :location, optional: true
  has_many :order_items, dependent: :destroy

  # Escopos de busca
  scope :by_number, lambda { |q| where('shopify_order_number ILIKE ?', "%#{q}%") if q.present? }
  scope :by_kinds,  lambda { |k| where(kinds: k) if k.present? }
  scope :by_staff,  lambda { |s| where('staff_name ILIKE ?', "%#{s}%") if s.present? }
  scope :by_date_from, lambda { |d| where('shopify_creation_date >= ?', d.to_date.beginning_of_day) if d.present? }
  scope :by_date_to,   lambda { |d| where('shopify_creation_date <= ?', d.to_date.end_of_day) if d.present? }

  # Helpers
  def total
    order_items.sum { |i| i.price.to_f * i.quantity.to_i }
  end

  def customer_name
    customer&.full_name.presence || 'Sem cliente'
  end

  def customer_phone
    customer&.phone.to_s
  end
end
