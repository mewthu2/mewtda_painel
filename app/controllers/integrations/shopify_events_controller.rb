class Integrations::ShopifyEventsController < IntegrationController
  def create
    ShopifyEvent.create!(
      integration_user: current_integration,
      event_name: params[:name],
      session_id: params[:session_id],
      payload: params.to_unsafe_h
    )

    head :ok
  end
end