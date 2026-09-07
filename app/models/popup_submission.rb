class PopupSubmission < ApplicationRecord
  belongs_to :popup

  STATUSES = %w[success shopify_error].freeze

  validates :name, presence: true
  validates :email, presence: true
  validates :status, inclusion: { in: STATUSES }

  def integrated?
    shopify_customer_id.present?
  end

  # shopify_customer_id vem como GID da API GraphQL (ex.: "gid://shopify/Customer/123")
  # — a URL do admin da Shopify precisa só do id numérico no final.
  def shopify_admin_customer_url
    return nil unless integrated?

    handle = popup.client.shopify_admin_handle
    return nil if handle.blank?

    numeric_id = shopify_customer_id.to_s.split('/').last
    "https://admin.shopify.com/store/#{handle}/customers/#{numeric_id}"
  end
end
