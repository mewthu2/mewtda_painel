module Tracking
  # Token assinado que a tela "Trackeamento site" entrega ao TrackingReportChannel:
  # diz qual relatório gerar (cliente + período) e pra qual usuário, sem o
  # navegador poder trocar o cliente.
  module ReportToken
    PURPOSE = :tracking_report

    def self.generate(user:, client:, period:, year: nil, month: nil)
      payload = { 'user_id' => user.id, 'client_id' => client.id, 'period' => period,
                  'year' => year, 'month' => month }
      verifier.generate(payload, expires_in: 1.hour)
    end

    # Hash com as chaves do generate, ou nil se o token for inválido/expirado.
    def self.read(token)
      verifier.verified(token.to_s)
    end

    def self.verifier
      Rails.application.message_verifier(PURPOSE)
    end
  end
end
