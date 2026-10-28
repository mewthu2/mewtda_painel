# Entrega o relatório da tela "Trackeamento site" quando o TrackingReportJob
# termina. O navegador assina com o token da página e chama `start`; o job só é
# enfileirado depois da assinatura, então a resposta nunca chega antes de alguém
# estar ouvindo.
class TrackingReportChannel < ApplicationCable::Channel
  def subscribed
    @report = Tracking::ReportToken.read(params[:token])
    return reject unless @report && @report['user_id'] == current_user.id

    stream_from self.class.stream_name(params[:token])
  end

  def start
    TrackingReportJob.perform_later(
      self.class.stream_name(params[:token]),
      @report['client_id'], @report['period'], @report['year'], @report['month']
    )
  end

  def self.stream_name(token)
    "tracking_report:#{Digest::SHA256.hexdigest(token.to_s).first(32)}"
  end
end
