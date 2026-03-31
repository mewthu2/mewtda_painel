module Shopify
  class Client
    attr_reader :client, :session

    def initialize(client)
      @db_client = client
      validate_credentials!
      setup_session
    end

    def query(graphql_query)
      response = @client.query(query: graphql_query)
      
      unless response.body.is_a?(Hash)
        raise StandardError, 'Resposta inválida da API Shopify'
      end

      if response.body['errors']
        error_messages = response.body['errors'].map { |e| e['message'] }.join(', ')
        raise StandardError, "Erros GraphQL: #{error_messages}"
      end

      response.body['data']
    end

    def post(path:, body:)
      @rest_client.post(path: path, body: body)
    end

    private

    def validate_credentials!
      unless @db_client.shopify_shop_url.present?
        raise ArgumentError, "Cliente #{@db_client.id} não possui shopify_shop_url configurado"
      end

      unless @db_client.shopify_access_token.present?
        raise ArgumentError, "Cliente #{@db_client.id} não possui shopify_access_token configurado"
      end
    end

    def setup_session
      @session = ShopifyAPI::Auth::Session.new(
        shop: @db_client.shopify_shop_url,
        access_token: @db_client.shopify_access_token
      )

      @client = ShopifyAPI::Clients::Graphql::Admin.new(session: @session)
      @rest_client = ShopifyAPI::Clients::Rest::Admin.new(session: @session)
    end
  end
end