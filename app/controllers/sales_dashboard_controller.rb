class SalesDashboardController < ApplicationController
  include ClientScoped

  before_action :set_client
  before_action :ensure_dashboard_access!
  before_action :require_admin!, only: [:sync_ad_costs]
  before_action :load_metrics, only: [:index]

  def index; end

  def sync_ad_costs
    unless @client
      return redirect_to sales_dashboard_path, alert: 'Nenhum cliente selecionado.'
    end

    year = requested_year
    month = requested_month

    results = AdCostSyncJob.new.perform(client_id: @client.id, year: year, month: month)

    if results.empty?
      redirect_to sales_dashboard_path(year: year, month: month), alert: 'Nenhuma integração de anúncio configurada para este cliente.'
    elsif results.any? { |r| r.status == :error }
      failed = results.select { |r| r.status == :error }
      failed.each do |result|
        Rails.logger.error(
          "[SalesDashboardController#sync_ad_costs] Falha ao sincronizar #{result.platform} " \
          "para client #{@client.id}: #{result.error_message}"
        )
      end

      redirect_to sales_dashboard_path(year: year, month: month),
                  alert: "Falha ao sincronizar: #{failed.map(&:platform).join(', ')}. Verifique as credenciais configuradas."
    else
      redirect_to sales_dashboard_path(year: year, month: month), notice: 'Custos sincronizados com sucesso.'
    end
  end

  private

  def ensure_dashboard_access!
    return if current_user.admin?
    return if @client&.sales_dashboard_enabled?

    redirect_to painel_path, alert: 'Dashboard de vendas não habilitado para este cliente.'
  end

  def load_metrics
    return unless @client

    @year = requested_year
    @month = requested_month
    @tag = params[:tag].presence

    @metrics = Sales::MonthlyMetrics.new(client: @client, year: @year, month: @month, tag: @tag).call
  end

  # Os parâmetros vêm da URL e podem ser editados à mão: sem limites, valores
  # como month=99 estouram em Time.zone.local / Date.new (ArgumentError -> 500).
  def requested_year
    (params[:year].presence || Date.current.year).to_i.clamp(2000, Date.current.year + 1)
  end

  def requested_month
    (params[:month].presence || Date.current.month).to_i.clamp(1, 12)
  end
end
