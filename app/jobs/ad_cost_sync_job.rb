class AdCostSyncJob < ApplicationJob
  queue_as :default

  Result = Struct.new(:platform, :status, :error_message)

  def perform(client_id:, year:, month:)
    client = Client.find(client_id)
    results = []

    if client.google_ads_configured?
      results << sync_platform(client: client, year: year, month: month, platform: 'google_ads') do
        GoogleAds::MonthlyCostFetcher.new(client: client, year: year, month: month).call
      end
    end

    if client.meta_configured?
      results << sync_platform(client: client, year: year, month: month, platform: 'meta') do
        Meta::MonthlyCostFetcher.new(client: client, year: year, month: month).call
      end
    end

    results
  end

  private

  def sync_platform(client:, year:, month:, platform:)
    cost = yield
    snapshot = AdCostSnapshot.find_or_initialize_by(client_id: client.id, platform: platform, year: year, month: month)
    snapshot.update!(cost: cost, fetched_at: Time.current)
    Result.new(platform, :ok, nil)
  rescue StandardError => e
    Rails.logger.error "[AdCostSyncJob] Falha ao sincronizar #{platform} para client #{client.id}: #{e.message}"
    Result.new(platform, :error, e.message)
  end
end
