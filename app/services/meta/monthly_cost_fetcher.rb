module Meta
  class MonthlyCostFetcher
    class FetchError < StandardError; end

    GRAPH_API_VERSION = 'v26.0'.freeze
    REQUEST_TIMEOUT = 15

    def initialize(client:, year:, month:)
      @client = client
      @year = year
      @month = month
    end

    def call
      since = Time.zone.local(@year, @month, 1).to_date
      until_date = since.end_of_month

      response = HTTParty.get(
        "https://graph.facebook.com/#{GRAPH_API_VERSION}/#{@client.meta_ad_account_id}/insights",
        query: {
          fields: 'spend',
          time_range: { since: since.iso8601, until: until_date.iso8601 }.to_json,
          access_token: @client.meta_access_token
        },
        timeout: REQUEST_TIMEOUT
      )

      unless response.success?
        message = response.parsed_response.dig('error', 'message') || 'Erro ao buscar custo do Meta Ads'
        raise FetchError, message
      end

      Array(response.parsed_response['data']).sum { |row| row['spend'].to_f }.round(2)
    end
  end
end
