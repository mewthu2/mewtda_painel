# app/controllers/integration_controller.rb
class IntegrationController < ActionController::API
  before_action :authenticate_integration!

  attr_reader :current_integration

  private

  def authenticate_integration!
    Rails.logger.warn "RAW AUTH HEADER: #{request.headers['Authorization'].inspect}"

    auth_header = request.headers['Authorization']
    return unauthorized unless auth_header

    token = auth_header.split(' ').last
    Rails.logger.warn "TOKEN RECEIVED: #{token.inspect}"

    integration = IntegrationUser.find_by(slug: 'greatpages', active: true)
    return unauthorized unless integration

    Rails.logger.warn "API KEY USED: #{integration.api_secret.inspect}"

    payload = Jwt::IntegrationToken.decode(token, integration)
    Rails.logger.warn "JWT PAYLOAD: #{payload.inspect}"

    return unauthorized unless payload

    @current_integration = integration
  end

  def unauthorized
    render json: { error: 'Unauthorized integration' }, status: :unauthorized
  end
end
