class Client < ApplicationRecord
  has_many :users, dependent: :nullify
  has_many :campaigns, dependent: :destroy

  validates :name, presence: true
  validates :email, presence: true

  def zapi_configured?
    zapi_instance_id.present? &&
      zapi_instance_token.present? &&
      zapi_client_token.present?
  end

  def shopify_configured?
    shopify_shop_url.present? && shopify_access_token.present?
  end
end