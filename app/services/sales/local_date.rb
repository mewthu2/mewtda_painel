module Sales
  # As colunas datetime são gravadas em "UTC equivalente" sem timezone
  # (config.active_record.default_timezone = :utc), mas o app e os clientes
  # operam em horário de Brasília (UTC-3, sem horário de verão desde 2019).
  # Agrupar direto por DATE(coluna) em SQL trunca usando UTC (a timezone da
  # sessão do Postgres) e empurra pedidos feitos à noite (~21h-23h59 local)
  # pro dia seguinte. Mesmo ajuste de -3h já usado em dashboard_controller.rb
  # e events_controller.rb.
  module LocalDate
    TIME_ZONE = 'America/Sao_Paulo'

    def self.sql(column)
      "DATE(#{column} - INTERVAL '3 hours')"
    end
  end
end
