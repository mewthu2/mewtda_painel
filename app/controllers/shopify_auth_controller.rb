class ShopifyAuthController < ApplicationController
  def auth
    shop = params[:shop]

    redirect_to(
      "https://#{shop}/admin/oauth/authorize?client_id=#{ENV['SHOPIFY_API_KEY']}&scope=read_orders,read_products,create_orders&redirect_uri=#{shopify_callback_url}&state=123",
      allow_other_host: true
    )
  end

  def callback
    shop = params[:shop]
    code = params[:code]

    response = HTTParty.post(
      "https://#{shop}/admin/oauth/access_token",
      body: {
        client_id: ENV['SHOPIFY_API_KEY'],
        client_secret: ENV['SHOPIFY_API_SECRET'],
        code:
      }
    )

    token = response.parsed_response['access_token']

    render json: { shop:, token: }
  end
end