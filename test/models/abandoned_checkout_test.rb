require 'test_helper'

class AbandonedCheckoutTest < ActiveSupport::TestCase
  def setup
    @client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
  end

  def create_checkout(attrs = {})
    @client.abandoned_checkouts.create!({
      shopify_checkout_id: SecureRandom.hex(6),
      phone: '+5511999999999',
      checkout_created_at: Time.current
    }.merge(attrs))
  end

  test 'with_phone excludes checkouts without a phone number' do
    with_phone = create_checkout
    create_checkout(phone: nil)
    create_checkout(phone: '')

    assert_equal [with_phone.id], AbandonedCheckout.with_phone.pluck(:id)
  end

  test 'pending_first_notification excludes recovered and already-notified checkouts' do
    pending = create_checkout
    create_checkout(first_notified_at: Time.current)
    create_checkout(completed_at: Time.current)

    assert_equal [pending.id], AbandonedCheckout.pending_first_notification.pluck(:id)
  end

  test 'pending_second_notification only includes checkouts notified once but not twice' do
    create_checkout # never notified
    awaiting_second = create_checkout(first_notified_at: 1.day.ago)
    create_checkout(first_notified_at: 2.days.ago, second_notified_at: Time.current)
    create_checkout(first_notified_at: 1.day.ago, completed_at: Time.current)

    assert_equal [awaiting_second.id], AbandonedCheckout.pending_second_notification.pluck(:id)
  end

  test 'status reflects recovery/notification progress' do
    assert_equal :pending, create_checkout.status
    assert_equal :first_sent, create_checkout(first_notified_at: Time.current).status
    assert_equal :second_sent, create_checkout(first_notified_at: 1.day.ago, second_notified_at: Time.current).status
    assert_equal :recovered, create_checkout(completed_at: Time.current).status
  end
end
