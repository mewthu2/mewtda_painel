class DailyRefundsSyncJob < ApplicationJob
  queue_as :default

  # Janela de 2 dias (não só "hoje") pra dar folga caso a execução de ontem falhe
  # ou atrase — sincronizar de novo um reembolso já salvo não duplica (upsert por
  # shopify_refund_id).
  def perform
    processed_at_min = 2.days.ago.beginning_of_day.iso8601
    processed_at_max = Time.current.iso8601

    Client.where(active: true).find_each do |client|
      next unless client.shopify_configured?

      RefundsSyncJob.perform_later(
        client_id: client.id,
        processed_at_min: processed_at_min,
        processed_at_max: processed_at_max
      )
    end
  end
end
