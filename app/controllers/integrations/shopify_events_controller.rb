class Integrations::ShopifyEventsController < IntegrationController
  def create
    ShopifyEvent.create!(
      client: current_integration.client,
      integration_user: current_integration,

      kind: params[:name],
      event_id: params[:id],
      event_name: params[:name],
      event_type: params[:type],

      session_id: params[:session_id] || params[:clientId],

      shop_domain: params.dig(:context, :shop_domain),
      event_timestamp: params[:timestamp],

      data: params[:data],
      context: params[:context],
      raw_payload: params.to_unsafe_h
    )

    head :ok
  end
end