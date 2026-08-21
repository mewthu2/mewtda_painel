require 'test_helper'

class DailyAdCostSyncJobTest < ActiveJob::TestCase
  def build_client(**attrs)
    Client.create!({ name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com" }.merge(attrs))
  end

  test 'enqueues AdCostSyncJob for clients with meta configured' do
    client = build_client(meta_access_token: 'token', meta_ad_account_id: 'act_1')

    assert_enqueued_with(job: AdCostSyncJob,
                         args: [{ client_id: client.id, year: Date.current.year,
                                  month: Date.current.month }]) do
      DailyAdCostSyncJob.perform_now
    end
  end

  test 'enqueues AdCostSyncJob for clients with google ads configured' do
    client = build_client(google_ads_refresh_token: 'refresh', google_ads_customer_id: '123')

    assert_enqueued_with(job: AdCostSyncJob,
                         args: [{ client_id: client.id, year: Date.current.year,
                                  month: Date.current.month }]) do
      DailyAdCostSyncJob.perform_now
    end
  end

  test 'skips clients with no ad platform configured' do
    build_client

    assert_no_enqueued_jobs(only: AdCostSyncJob) do
      DailyAdCostSyncJob.perform_now
    end
  end
end
