require 'test_helper'
require 'minitest/mock'

class AdCostSyncJobTest < ActiveJob::TestCase
  class FakeFetcher
    def initialize(*); end
    def call = 123.45
  end

  class RaisingFetcher
    def initialize(*); end
    def call = raise GoogleAds::MonthlyCostFetcher::FetchError, 'Token expirado'
  end

  def build_client(**attrs)
    Client.create!({ name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com" }.merge(attrs))
  end

  test 'skips platforms without credentials configured' do
    client = build_client

    results = AdCostSyncJob.new.perform(client_id: client.id, year: 2026, month: 3)

    assert_empty results
  end

  test 'upserts an ad_cost_snapshot for each configured platform that succeeds' do
    client = build_client(meta_access_token: 'token', meta_ad_account_id: 'act_1')

    Meta::MonthlyCostFetcher.stub :new, ->(**) { FakeFetcher.new } do
      results = AdCostSyncJob.new.perform(client_id: client.id, year: 2026, month: 3)

      assert_equal 1, results.length
      assert_equal 'meta', results.first.platform
      assert_equal :ok, results.first.status
    end

    snapshot = AdCostSnapshot.find_by(client_id: client.id, platform: 'meta', year: 2026, month: 3)
    assert_equal 123.45, snapshot.cost.to_f
  end

  test 'records an error result without touching the snapshot when the fetcher raises' do
    client = build_client(google_ads_refresh_token: 'refresh', google_ads_customer_id: '123')

    GoogleAds::MonthlyCostFetcher.stub :new, ->(**) { RaisingFetcher.new } do
      results = AdCostSyncJob.new.perform(client_id: client.id, year: 2026, month: 3)

      assert_equal 1, results.length
      assert_equal 'google_ads', results.first.platform
      assert_equal :error, results.first.status
      assert_equal 'Token expirado', results.first.error_message
    end

    assert_nil AdCostSnapshot.find_by(client_id: client.id, platform: 'google_ads', year: 2026, month: 3)
  end
end
