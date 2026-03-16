class IntegrationController < ActionController::API
  before_action :authenticate_integration!

  attr_reader :current_integration

  private

  def authenticate_integration!
    raw_header = request.headers['Authorization']

    Rails.logger.warn "RAW AUTH HEADER: #{raw_header.inspect}"

    token = raw_header.to_s.split(' ').last

    Rails.logger.warn "TOKEN RECEIVED: #{token.inspect}"

    integration = IntegrationUser.find_by(api_secret: token, active: true)

    unless integration
      render json: { error: 'Unauthorized' }, status: :unauthorized
      return
    end

    @current_integration = integration
  end
end