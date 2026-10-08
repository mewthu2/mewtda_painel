# Todo dia de madrugada: atualiza os produtos guardados das landing pages no ar
# (ver LandingPages::SyncProducts).
class LandingPagesProductsSyncJob < ApplicationJob
  queue_as :default

  def perform
    LandingPage.active.includes(:client).find_each do |landing_page|
      next unless landing_page.client.storefront_configured?

      result = LandingPages::SyncProducts.new(landing_page).call
      Rails.logger.error("[LandingPagesProductsSyncJob] #{landing_page.public_path}: #{result.error}") unless result.ok
    end
  end
end
