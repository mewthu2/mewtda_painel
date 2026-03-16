module ShopifyEvents
  class Track
    attr_reader :integration, :payload

    def initialize(integration:, payload:)
      @integration = integration
      @payload = payload
    end

    def call
      ShopifyEvent.create!(
        client: integration.client,
        integration_user: integration,
        kind: payload["name"],
        shopify_event_id: payload["id"],
        session_id: session_id,
        payload: payload
      )
    end

    private

    def session_id
      payload.dig("context", "session_id") ||
      payload.dig("context", "sessionId") ||
      payload.dig("clientId") ||
      SecureRandom.uuid
    end
  end
end