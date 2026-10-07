class LandingPageLead < ApplicationRecord
  belongs_to :landing_page

  STATUSES = %w[success shopify_error].freeze
  UTM_FIELDS = %w[utm_source utm_medium utm_campaign utm_content utm_term].freeze

  before_validation { self.email = email.to_s.strip.downcase }

  validates :name, :email, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, uniqueness: { scope: :landing_page_id }
  validates :status, inclusion: { in: STATUSES }

  scope :new_customers, -> { where(existing_customer: false) }
  scope :existing_customers, -> { where(existing_customer: true) }

  # shopify_customer_id vem como GID ("gid://shopify/Customer/123").
  def shopify_admin_customer_url
    return nil if shopify_customer_id.blank?

    handle = landing_page.client.shopify_admin_handle
    return nil if handle.blank?

    "https://admin.shopify.com/store/#{handle}/customers/#{shopify_customer_id.to_s.split('/').last}"
  end
end
