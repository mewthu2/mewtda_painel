module Integrations
  class ShopifyEventsController < IntegrationController
    def create
      Rails.logger.info('SHOPIFY EVENT RECEIVED')

      payload = JSON.parse(request.raw_post)

      Rails.logger.info(payload)

      ShopifyEvents::Track.new(
        integration: current_integration,
        payload:
      ).call

      head :ok
    end
  end
end