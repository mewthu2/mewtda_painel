require 'test_helper'
require 'minitest/mock'

class Meta::MonthlyCostFetcherTest < ActiveSupport::TestCase
  FakeResponse = Struct.new(:success?, :parsed_response)

  def build_client
    Client.create!(
      name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com",
      meta_access_token: 'token123', meta_ad_account_id: 'act_1'
    )
  end

  test 'sums spend across all rows returned by the Graph API' do
    client = build_client
    response = FakeResponse.new(true, { 'data' => [{ 'spend' => '120.50' }, { 'spend' => '30.25' }] })

    HTTParty.stub :get, response do
      cost = Meta::MonthlyCostFetcher.new(client: client, year: 2026, month: 3).call
      assert_equal 150.75, cost
    end
  end

  test 'returns 0 when the Graph API returns no rows for the period' do
    client = build_client
    response = FakeResponse.new(true, { 'data' => [] })

    HTTParty.stub :get, response do
      cost = Meta::MonthlyCostFetcher.new(client: client, year: 2026, month: 3).call
      assert_equal 0, cost
    end
  end

  test 'raises FetchError with the API message when the call fails' do
    client = build_client
    response = FakeResponse.new(false, { 'error' => { 'message' => 'Invalid OAuth access token' } })

    HTTParty.stub :get, response do
      error = assert_raises(Meta::MonthlyCostFetcher::FetchError) do
        Meta::MonthlyCostFetcher.new(client: client, year: 2026, month: 3).call
      end
      assert_equal 'Invalid OAuth access token', error.message
    end
  end
end
