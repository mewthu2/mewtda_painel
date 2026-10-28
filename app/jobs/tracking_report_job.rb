# Gera o relatório da tela "Trackeamento site" fora da requisição web (as
# consultas nos eventos do pixel estouravam o timeout de 30s do Heroku) e devolve
# o HTML pronto pelo TrackingReportChannel.
class TrackingReportJob < ApplicationJob
  queue_as :default

  def perform(stream, client_id, period, year, month)
    client = Client.find(client_id)
    assigns = Tracking::DashboardReport.new(client: client, period: period, year: year, month: month).assigns
    html = DashboardController.render(partial: 'dashboard/report', assigns: assigns)

    ActionCable.server.broadcast(stream, { html: html })
  rescue StandardError => e
    # Sem retry: quem está esperando é a tela aberta, não adianta tentar de novo
    # minutos depois.
    Rails.logger.error("[TrackingReportJob] #{e.class}: #{e.message}")
    ActionCable.server.broadcast(stream, { error: 'Não foi possível carregar os dados. Tente novamente.' })
  end
end
