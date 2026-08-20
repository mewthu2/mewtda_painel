module GoogleAds
  class MonthlyCostFetcher
    class FetchError < StandardError; end

    API_VERSION = 'v25'.freeze
    TOKEN_URL = 'https://oauth2.googleapis.com/token'.freeze
    REQUEST_TIMEOUT = 15

    def initialize(client:, year:, month:)
      @client = client
      @year = year
      @month = month
    end

    def call
      access_token = fetch_access_token
      cost_micros = fetch_cost_micros(access_token)
      (cost_micros / 1_000_000.0).round(2)
    end

    private

    def fetch_access_token
      response = HTTParty.post(
        TOKEN_URL,
        body: {
          client_id: ENV['GOOGLE_ADS_CLIENT_ID'],
          client_secret: ENV['GOOGLE_ADS_CLIENT_SECRET'],
          refresh_token: @client.google_ads_refresh_token,
          grant_type: 'refresh_token'
        },
        timeout: REQUEST_TIMEOUT
      )

      raise FetchError, 'Token do Google Ads expirado ou revogado' unless response.success?

      response.parsed_response['access_token']
    end

    def fetch_cost_micros(access_token)
      since = Time.zone.local(@year, @month, 1).to_date
      until_date = since.end_of_month
      customer_id = @client.google_ads_customer_id.to_s.delete('-')

      response = HTTParty.post(
        "https://googleads.googleapis.com/#{API_VERSION}/customers/#{customer_id}/googleAds:searchStream",
        headers: {
          'Authorization' => "Bearer #{access_token}",
          'developer-token' => ENV['GOOGLE_ADS_DEVELOPER_TOKEN'],
          'login-customer-id' => ENV['GOOGLE_ADS_LOGIN_CUSTOMER_ID'].to_s.delete('-'),
          'Content-Type' => 'application/json'
        },
        body: {
          query: "SELECT metrics.cost_micros FROM customer WHERE segments.date BETWEEN '#{since.iso8601}' AND '#{until_date.iso8601}'"
        }.to_json,
        timeout: REQUEST_TIMEOUT
      )

      raise FetchError, 'Erro ao buscar custo do Google Ads' unless response.success?

      Array(response.parsed_response).sum do |chunk|
        Array(chunk['results']).sum { |result| result.dig('metrics', 'costMicros').to_i }
      end
    end
  end
end
