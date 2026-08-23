class SendCartRecoveryNotificationJob < ApplicationJob
  queue_as :default

  def perform(abandoned_checkout_id, template, coupon_code, slot)
    checkout = AbandonedCheckout.find(abandoned_checkout_id)
    return if checkout.phone.blank?

    message = build_message(template, checkout, coupon_code)
    response = Zapi::Client.new(checkout.client).send_text(phone: format_phone(checkout.phone), message: message)
    success = response.is_a?(Hash) && response['zaapId'].present?

    if slot.to_s == 'first'
      checkout.update!(first_notified_at: Time.current, first_message_sent: success ? message : nil,
                       first_coupon_code: coupon_code)
    else
      checkout.update!(second_notified_at: Time.current, second_message_sent: success ? message : nil,
                       second_coupon_code: coupon_code)
    end
  end

  private

  def build_message(template, checkout, coupon_code)
    name = checkout.customer&.name.presence || 'cliente'

    template.to_s
            .gsub('{nome}', name)
            .gsub('{cupom}', coupon_code.to_s)
            .gsub('{link}', checkout.recovery_url.to_s)
  end

  def format_phone(phone)
    digits = phone.to_s.gsub(/\D/, '')
    digits.start_with?('55') ? digits : "55#{digits}"
  end
end
