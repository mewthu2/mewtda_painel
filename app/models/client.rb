class Client < ApplicationRecord
  has_many :users, dependent: :nullify
  has_many :campaigns, dependent: :destroy
  has_many :ad_costs, dependent: :destroy
  has_many :refunds, dependent: :destroy
  has_many :goals, dependent: :destroy
  has_many :abandoned_checkouts, dependent: :destroy
  has_one :popup, dependent: :destroy
  has_many :email_templates, dependent: :destroy
  has_one :exchange_config, dependent: :destroy
  has_many :exchange_requests, dependent: :destroy

  encrypts :meta_access_token, :google_ads_refresh_token, :shopify_api_secret

  validates :name, presence: true
  validates :email, presence: true
  validates :site_url, format: { with: %r{\Ahttps?://}, message: 'deve começar com http:// ou https://' },
                       allow_blank: true
  validates :email_sending_domain,
            format: { with: /\A([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}\z/i,
                      message: 'não parece um domínio válido' },
            allow_blank: true

  def site_url_configured?
    site_url.present?
  end

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

  def ses_domain_verified?
    ses_verification_status == 'verified'
  end

  # Registros CNAME do Easy DKIM da SES — cada token vira um registro que o
  # cliente precisa cadastrar no DNS do domínio pra provar a propriedade e
  # habilitar o DKIM (formato padrão da AWS quando a identidade é criada sem
  # configuração de assinatura customizada).
  def ses_dns_records
    return [] if email_sending_domain.blank? || ses_dkim_tokens.blank?

    ses_dkim_tokens.map do |token|
      {
        name: "#{token}._domainkey.#{email_sending_domain}",
        type: 'CNAME',
        value: "#{token}.dkim.amazonses.com"
      }
    end
  end
end
