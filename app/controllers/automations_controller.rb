class AutomationsController < ApplicationController
  include ClientScoped

  before_action :set_client
  before_action :require_client!

  def index
    @tracking_campaign = @client.campaigns.find_by(kind: :shipping_tracking)
  end

  def edit_tracking
    @campaign = tracking_campaign
  end

  def update_tracking
    @campaign = tracking_campaign
    if @campaign.update(tracking_params)
      redirect_to automations_path, notice: 'Automação de rastreio salva com sucesso.'
    else
      render :edit_tracking, status: :unprocessable_entity
    end
  end

  private

  def require_client!
    redirect_to crm_path, alert: 'Nenhum cliente selecionado.' unless @client
  end

  # Só existe uma automação de rastreio por cliente — carrega a existente ou
  # prepara uma nova com valores padrão, sem persistir ainda.
  def tracking_campaign
    @client.campaigns.find_or_initialize_by(kind: :shipping_tracking) do |c|
      c.name = 'Notificação de Rastreio'
      c.start_date = Date.current
      c.end_date = Date.current + 1.year
      c.max_sends = 3
      c.interval_days = 4
    end
  end

  def tracking_params
    params.require(:campaign)
          .permit(:name, :message, :start_date, :end_date, :active, :max_sends, :interval_days)
          .merge(kind: :shipping_tracking)
  end
end
