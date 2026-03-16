module Integrations
  class ShopifyEventsController < IntegrationController
    skip_before_action :authenticate_integration!, if: -> { request.options? }

    def create
      return head :ok if request.options?

      payload = JSON.parse(request.raw_post)

      ShopifyEvents::Track.new(
        integration: current_integration,
        payload: payload
      ).call

      head :ok
    end
  end
end