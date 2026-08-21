class GoalsController < ApplicationController
  include ClientScoped

  before_action :set_client
  before_action :ensure_client!
  before_action :load_goal

  def edit; end

  def update
    if @goal.update(goal_params)
      redirect_to sales_dashboard_path(year: @year, month: @month), notice: 'Meta salva com sucesso.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def ensure_client!
    return if @client

    redirect_to crm_path, alert: 'Nenhum cliente selecionado.'
  end

  def load_goal
    @year = requested_year
    @month = requested_month
    @goal = @client.goals.find_or_initialize_by(year: @year, month: @month)
  end

  def goal_params
    params.require(:goal).permit(
      :revenue_target, :roas_target, :avg_ticket_target, :conversion_rate_target,
      :cac_target, :tagged_revenue_target, :tagged_revenue_tag
    )
  end

  # Mesma proteção usada no SalesDashboardController: parâmetros vêm da URL e
  # podem ser editados à mão.
  def requested_year
    (params[:year].presence || Date.current.year).to_i.clamp(2000, Date.current.year + 1)
  end

  def requested_month
    (params[:month].presence || Date.current.month).to_i.clamp(1, 12)
  end
end
