require 'test_helper'

class Exchange::EligibilityCalculatorTest < ActiveSupport::TestCase
  def build_config(return_window_days: 7)
    client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
    ExchangeConfig.create!(client: client, return_window_days: return_window_days)
  end

  test 'returns :cancelled when the order was cancelled' do
    result = Exchange::EligibilityCalculator.new(build_config).call(cancelled: true, fulfilled_at: 1.day.ago)
    assert_equal :cancelled, result
  end

  test 'returns :not_fulfilled when there is no fulfillment date' do
    result = Exchange::EligibilityCalculator.new(build_config).call(cancelled: false, fulfilled_at: nil)
    assert_equal :not_fulfilled, result
  end

  test 'returns :return_and_exchange within the return window' do
    result = Exchange::EligibilityCalculator.new(build_config(return_window_days: 7)).call(
      cancelled: false, fulfilled_at: 3.days.ago
    )
    assert_equal :return_and_exchange, result
  end

  test 'returns :return_and_exchange exactly on the last day of the window' do
    result = Exchange::EligibilityCalculator.new(build_config(return_window_days: 7)).call(
      cancelled: false, fulfilled_at: 7.days.ago
    )
    assert_equal :return_and_exchange, result
  end

  test 'returns :exchange_only past the return window' do
    result = Exchange::EligibilityCalculator.new(build_config(return_window_days: 7)).call(
      cancelled: false, fulfilled_at: 8.days.ago
    )
    assert_equal :exchange_only, result
  end
end
