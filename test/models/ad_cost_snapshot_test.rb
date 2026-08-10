require 'test_helper'

class AdCostSnapshotTest < ActiveSupport::TestCase
  def build_client
    Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
  end

  test 'valid with a known platform, year, month and non-negative cost' do
    snapshot = AdCostSnapshot.new(
      client: build_client, platform: 'meta', year: 2026, month: 3, cost: 150.0, fetched_at: Time.current
    )
    assert snapshot.valid?
  end

  test 'invalid with an unknown platform' do
    snapshot = AdCostSnapshot.new(
      client: build_client, platform: 'tiktok', year: 2026, month: 3, cost: 150.0
    )
    I18n.with_locale(:en) do
      assert_not snapshot.valid?
      assert_includes snapshot.errors[:platform], 'is not included in the list'
    end
  end

  test 'invalid with a negative cost' do
    snapshot = AdCostSnapshot.new(
      client: build_client, platform: 'meta', year: 2026, month: 3, cost: -1
    )
    assert_not snapshot.valid?
  end

  test 'unique per client, platform, year and month' do
    client = build_client
    AdCostSnapshot.create!(client: client, platform: 'meta', year: 2026, month: 3, cost: 100)

    duplicate = AdCostSnapshot.new(client: client, platform: 'meta', year: 2026, month: 3, cost: 200)

    assert_not duplicate.valid?
  end
end
