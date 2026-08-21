class SalesDashboardController < ApplicationController
  include ClientScoped

  before_action :set_client
  before_action :ensure_dashboard_access!
  before_action :require_admin!, only: %i[sync_ad_costs process_now]
  before_action :load_metrics, only: %i[index export_xlsx]

  def index; end

  def export_xlsx
    unless @client
      return redirect_to sales_dashboard_path, alert: 'Nenhum cliente selecionado.'
    end

    workbook = RubyXL::Workbook.new
    worksheet = workbook[0]
    worksheet.sheet_name = 'Resumo'

    rows = [
      ['Cliente', @client.name],
      ['Período', "#{@month}/#{@year}"],
      [],
      ['Bruto', @metrics[:gross_sales]],
      ['Descontos', -@metrics[:discounts]],
      ['Faturamento (líquido)', @metrics[:net_of_discounts]],
      ['Frete', @metrics[:shipping]],
      ['Faturamento', @metrics[:revenue]],
      [],
      ['Pedidos', @metrics[:orders_count]],
      ['Ticket Médio', @metrics[:avg_ticket]],
      [],
      ['Investimento em Anúncios', @metrics[:ad_cost]],
      ['ROAS', @metrics[:roas]],
      ['Novos Clientes', @metrics[:new_customers_count]],
      ['CAC', @metrics[:cac]]
    ]

    rows.each_with_index do |row, i|
      row.each_with_index { |value, j| worksheet.add_cell(i, j, value) }
    end

    file_path = Rails.root.join('tmp', "vendas_#{SecureRandom.hex(4)}.xlsx")
    workbook.write(file_path.to_s)

    send_file file_path,
              filename: "vendas_#{@client.name.parameterize}_#{@month}_#{@year}.xlsx",
              type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
              disposition: 'attachment'
  end

  def sync_ad_costs
    unless @client
      return redirect_to sales_dashboard_path, alert: 'Nenhum cliente selecionado.'
    end

    year = requested_year
    month = requested_month

    results = AdCostSyncJob.new.perform(client_id: @client.id, year: year, month: month)

    if results.empty?
      redirect_to sales_dashboard_path(year: year, month: month),
                  alert: 'Nenhuma integração de anúncio configurada para este cliente.'
    elsif results.any? { |r| r.status == :error }
      failed = results.select { |r| r.status == :error }
      failed.each do |result|
        Rails.logger.error(
          "[SalesDashboardController#sync_ad_costs] Falha ao sincronizar #{result.platform} " \
          "para client #{@client.id}: #{result.error_message}"
        )
      end

      alert = "Falha ao sincronizar: #{failed.map(&:platform).join(', ')}. Verifique as credenciais configuradas."
      redirect_to sales_dashboard_path(year: year, month: month), alert: alert
    else
      redirect_to sales_dashboard_path(year: year, month: month), notice: 'Custos sincronizados com sucesso.'
    end
  end

  # Sincroniza os pedidos do mês em exibição na hora, sob demanda (em vez de
  # esperar o job agendado). Reembolsos não entram mais aqui — saíram da
  # equação do faturamento, então não há motivo pra sincronizar isso agora.
  def process_now
    unless @client
      return redirect_to sales_dashboard_path, alert: 'Nenhum cliente selecionado.'
    end

    unless @client.shopify_configured?
      return redirect_to sales_dashboard_path(year: requested_year, month: requested_month),
                         alert: 'Shopify não configurado para este cliente.'
    end

    year = requested_year
    month = requested_month
    month_start = Time.zone.local(year, month, 1).beginning_of_day
    month_end = month_start.end_of_month

    session = ShopifyAPI::Auth::Session.new(shop: @client.shopify_shop_url, access_token: @client.shopify_access_token)

    orders_count = Shopify::Orders.sync_shopify_orders_to_rails(
      session: session, client: @client, limit: 250, status: 'any',
      created_at_min: month_start.iso8601, created_at_max: month_end.iso8601
    )

    redirect_to sales_dashboard_path(year: year, month: month), notice: "#{orders_count} pedidos processados."
  rescue StandardError => e
    Rails.logger.error("[SalesDashboardController#process_now] client #{@client&.id}: #{e.class} #{e.message}")
    redirect_to sales_dashboard_path(year: requested_year, month: requested_month),
                alert: "Falha ao processar: #{e.message}"
  end

  private

  def ensure_dashboard_access!
    return if current_user.admin?
    return if @client.present?

    redirect_to crm_path, alert: 'Nenhum cliente vinculado à sua conta.'
  end

  def load_metrics
    return unless @client

    @year = requested_year
    @month = requested_month
    @tag = params[:tag].presence

    @metrics = Sales::MonthlyMetrics.new(client: @client, year: @year, month: @month, tag: @tag).call
    @daily = Sales::DailyBreakdown.new(client: @client, year: @year, month: @month).call
    @goal_daily = Sales::GoalDailyBreakdown.new(
      client: @client, year: @year, month: @month, tag: @metrics[:tagged_revenue_tag]
    ).call
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
