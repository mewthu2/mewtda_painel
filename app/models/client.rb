class Client < ApplicationRecord
  has_many :users, dependent: :nullify
  has_many :campaigns, dependent: :destroy
  has_many :ad_costs, dependent: :destroy
  has_many :refunds, dependent: :destroy
  has_many :goals, dependent: :destroy

  encrypts :meta_access_token, :google_ads_refresh_token, :shopify_api_secret

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

  def shopify_admin_handle
    shopify_shop_url.to_s.sub(%r{\Ahttps?://}, '').split('.').first
  end

  def shopify_app_configured?
    shopify_api_key.present? && shopify_api_secret.present?
  end

  def meta_configured?
    meta_access_token.present? && meta_ad_account_id.present?
  end

  def google_ads_configured?
    google_ads_refresh_token.present? && google_ads_customer_id.present?
  end
end
