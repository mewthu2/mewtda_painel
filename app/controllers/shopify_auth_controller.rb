class ShopifyAuthController < ApplicationController
  skip_before_action :authenticate_user!, only: [:auth, :callback]

  STATE_EXPIRY = 15.minutes
  SCOPE = 'read_orders,write_orders,read_products'.freeze

  def auth
    client = Client.find(params[:id])
    shop = params[:shop]

    unless client.shopify_app_configured?
      return render plain: 'App Shopify não configurado para este cliente.', status: :unprocessable_entity
    end

    state = verifier.generate(client.id, expires_in: STATE_EXPIRY)

    redirect_to(
      "https://#{shop}/admin/oauth/authorize?client_id=#{client.shopify_api_key}&scope=#{SCOPE}&redirect_uri=#{shopify_callback_url}&state=#{state}",
      allow_other_host: true
    )
  end

  def callback
    client_id = verifier.verify(params[:state])
    client = Client.find(client_id)

    shop = params[:shop]
    code = params[:code]

    response = HTTParty.post(
      "https://#{shop}/admin/oauth/access_token",
      body: {
        client_id: client.shopify_api_key,
        client_secret: client.shopify_api_secret,
        code:
      }
    )

    token = response.parsed_response['access_token']

    unless token.present?
      return render plain: 'Não foi possível conectar ao Shopify.', status: :unprocessable_entity
    end

    client.update!(shopify_shop_url: shop, shopify_access_token: token)

    redirect_to edit_client_path(client), notice: 'Shopify conectado com sucesso.'
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
    render plain: 'Estado inválido na conexão com o Shopify.', status: :unprocessable_entity
  end

  private

  def verifier
    Rails.application.message_verifier(:shopify_oauth_state)
  end
end
