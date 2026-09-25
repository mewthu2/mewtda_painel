class SendExchangeEmailJob < ApplicationJob
  queue_as :default

  SUBJECT_FIELDS = {
    'requested' => :requested_email_subject,
    'approved' => :approved_email_subject,
    'rejected' => :rejected_email_subject,
    'completed' => :completed_email_subject
  }.freeze

  BODY_FIELDS = {
    'requested' => :requested_email_body,
    'approved' => :approved_email_body,
    'rejected' => :rejected_email_body,
    'completed' => :completed_email_body
  }.freeze

  def perform(exchange_request_id:, kind:)
    exchange_request = ExchangeRequest.find(exchange_request_id)
    client = exchange_request.client
    config = client.exchange_config

    unless config
      Rails.logger.warn "[SendExchangeEmailJob] Client #{client.id} não tem ExchangeConfig — pulando envio"
      return
    end

    Ses::SendEmailService.new(client).call(
      to: exchange_request.customer_email,
      subject: interpolate(config.public_send(SUBJECT_FIELDS.fetch(kind)), exchange_request),
      html_body: interpolate(config.public_send(BODY_FIELDS.fetch(kind)), exchange_request)
    )
  rescue StandardError => e
    Rails.logger.error "[SendExchangeEmailJob] Falha para exchange_request #{exchange_request_id}: #{e.message}"
  end

  private

  def interpolate(text, exchange_request)
    text.to_s
        .gsub('{{customer_name}}', exchange_request.customer_name.to_s)
        .gsub('{{order_number}}', exchange_request.shopify_order_number.to_s)
        .gsub('{{coupon_code}}', exchange_request.coupon_code.to_s)
  end
end
