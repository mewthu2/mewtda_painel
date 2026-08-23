require 'test_helper'

class ProcessCartRecoveryCampaignsJobTest < ActiveJob::TestCase
  def setup
    @client = Client.create!(
      name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com",
      zapi_instance_id: 'inst', zapi_instance_token: 'tok', zapi_client_token: 'ctok'
    )
  end

  def create_campaign(attrs = {})
    @client.campaigns.create!({
      name: 'Recuperação', kind: 'cart_recovery', message: 'Oi {nome}',
      start_date: Date.current - 1.day, end_date: Date.current + 1.year,
      send_delay_minutes: 60
    }.merge(attrs))
  end

  def create_checkout(attrs = {})
    @client.abandoned_checkouts.create!({
      shopify_checkout_id: SecureRandom.hex(6), phone: '+5511999999999',
      checkout_created_at: Time.current
    }.merge(attrs))
  end

  test 'sends the first message once the delay has passed for a pending checkout' do
    create_campaign
    checkout = create_checkout(checkout_created_at: 2.hours.ago)

    assert_enqueued_with(job: SendCartRecoveryNotificationJob, args: [checkout.id, 'Oi {nome}', nil, 'first']) do
      ProcessCartRecoveryCampaignsJob.perform_now(@client.id)
    end
  end

  test 'does not send before the configured delay has passed' do
    create_campaign(send_delay_minutes: 120)
    create_checkout(checkout_created_at: 10.minutes.ago)

    assert_no_enqueued_jobs(only: SendCartRecoveryNotificationJob) do
      ProcessCartRecoveryCampaignsJob.perform_now(@client.id)
    end
  end

  test 'sends the resend message when enabled and the resend delay has passed' do
    create_campaign(resend_enabled: true, resend_delay_hours: 24, resend_message: 'Volta, {nome}!')
    checkout = create_checkout(checkout_created_at: 2.days.ago, first_notified_at: 2.days.ago)

    assert_enqueued_with(job: SendCartRecoveryNotificationJob,
                         args: [checkout.id, 'Volta, {nome}!', nil, 'second']) do
      ProcessCartRecoveryCampaignsJob.perform_now(@client.id)
    end
  end

  test 'skips clients without zapi configured' do
    @client.update!(zapi_instance_id: nil, zapi_instance_token: nil, zapi_client_token: nil)
    create_campaign
    create_checkout(checkout_created_at: 2.hours.ago)

    assert_no_enqueued_jobs(only: SendCartRecoveryNotificationJob) do
      ProcessCartRecoveryCampaignsJob.perform_now(@client.id)
    end
  end
end
