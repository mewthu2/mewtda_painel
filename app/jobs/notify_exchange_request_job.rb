# Notifica a equipe da Mewtda (não o lojista) via WhatsApp quando chega uma
# nova solicitação de troca/devolução, em qualquer cliente. Usa sempre a
# instância Zapi global da Mewtda (ENV) — client: nil força o fallback global
# já existente em Zapi::Client, nunca usa a instância Zapi do lojista.
class NotifyExchangeRequestJob < ApplicationJob
  queue_as :default

  def perform(exchange_request_id:)
    phone = ENV['ZAPI_NOTIFICATION_PHONE']
    return if phone.blank?

    exchange_request = ExchangeRequest.find(exchange_request_id)

    Zapi::Client.new(nil).send_text(phone: format_phone(phone), message: build_message(exchange_request))
  rescue StandardError => e
    Rails.logger.error "[NotifyExchangeRequestJob] Falha para exchange_request #{exchange_request_id}: #{e.message}"
  end

  private

  def build_message(exchange_request)
    items_summary = exchange_request.exchange_request_items.map { |item| "- #{item.product_name} (#{item.kind})" }.join("\n")

    <<~MSG
      🔁 Nova solicitação de troca/devolução

      Loja: #{exchange_request.client.name}
      Pedido: #{exchange_request.shopify_order_number}
      Cliente: #{exchange_request.customer_name.presence || exchange_request.customer_email}

      Itens:
      #{items_summary}
    MSG
  end

  def format_phone(phone)
    digits = phone.to_s.gsub(/\D/, '')
    digits.start_with?('55') ? digits : "55#{digits}"
  end
end
