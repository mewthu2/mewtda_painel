# app/services/jwt/integration_token.rb
require 'jwt'

module Jwt
  class IntegrationToken
    ALGORITHM = 'HS256'

    def self.encode(integration_user)
      payload = {
        sub: integration_user.id,
        slug: integration_user.slug,
        exp: 10.years.from_now.to_i
      }

      JWT.encode(payload, integration_user.api_secret, ALGORITHM)
    end

    def self.decode(token, integration_user)
      JWT.decode(
        token,
        integration_user.api_secret,
        true,
        algorithm: ALGORITHM
      ).first
    rescue JWT::DecodeError, JWT::ExpiredSignature
      nil
    end
  end
end
