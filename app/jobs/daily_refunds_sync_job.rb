# Desativado: reembolsos saíram da equação de Faturamento (Sales::MonthlyMetrics
# usa só pedidos não cancelados agora, sem dedução de reembolso). Pode remover
# essa entrada do Heroku Scheduler — o job continua aqui, e no.op, caso decidam
# reativar o rastreio de reembolsos no futuro.
class DailyRefundsSyncJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info('[DailyRefundsSyncJob] Desativado — reembolsos não fazem mais parte do cálculo de faturamento.')
  end
end
