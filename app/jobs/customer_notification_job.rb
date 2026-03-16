class CustomerNotificationJob < ApplicationJob
  queue_as :default

  def perform(order_id, coupon_code, type)
    order = Order.includes(:customer).find(order_id)
    customer = order.customer

    phone = customer.default_address_phone
    return unless phone.present?

    message =
      case type.to_sym
      when :purchase
        purchase_message(customer, coupon_code)
      when :expiring
        expiring_message(customer, coupon_code)
      end

    Zapi::Client.send_text(
      phone: format_phone(phone),
      message:
    )
  end

  private

  def purchase_message(customer, coupon)
    <<~MSG
    🎉 Obrigado pela sua compra!

    Você ganhou *8% de cashback* para a próxima compra.

    Seu cupom:
    #{coupon}

    ⏳ Válido por 30 dias.

    Aproveite!
    MSG
  end

  def expiring_message(customer, coupon)
    <<~MSG
    ⏰ Seu cupom está quase expirando!

    Cupom:
    #{coupon}

    Use hoje e ganhe *8% de desconto*.

    Não perca 😉
    MSG
  end

  def format_phone(phone)
    digits = phone.gsub(/\D/, '')
    digits.start_with?('55') ? digits : "55#{digits}"
  end
end