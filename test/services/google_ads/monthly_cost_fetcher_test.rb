require 'test_helper'
require 'minitest/mock'

class GoogleAds::MonthlyCostFetcherTest < ActiveSupport::TestCase
  FakeResponse = Struct.new(:success?, :parsed_response)

  def build_client
    Client.create!(
      name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com",
      google_ads_refresh_token: 'refresh-token', google_ads_customer_id: '1234567890'
    )
  end

  test 'exchanges the refresh token and sums cost_micros across result chunks' do
    client = build_client

    responder = lambda do |_url, _options|
      if _url == 'https://oauth2.googleapis.com/token'
        FakeResponse.new(true, { 'access_token' => 'access-123' })
      else
        FakeResponse.new(true, [
                           { 'results' => [{ 'metrics' => { 'costMicros' => '2000000' } }] },
                           { 'results' => [{ 'metrics' => { 'costMicros' => '500000' } }] }
                         ])
      end
    end

    HTTParty.stub :post, responder do
      cost = GoogleAds::MonthlyCostFetcher.new(client: client, year: 2026, month: 3).call
      assert_equal 2.5, cost
    end
  end

  test 'raises FetchError when the token exchange fails' do
    client = build_client
    response = FakeResponse.new(false, { 'error' => 'invalid_grant' })

    HTTParty.stub :post, response do
      assert_raises(GoogleAds::MonthlyCostFetcher::FetchError) do
        GoogleAds::MonthlyCostFetcher.new(client: client, year: 2026, month: 3).call
      end
    end
  end
end
