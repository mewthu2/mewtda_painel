class AdCostsController < ApplicationController
  include ClientScoped

  before_action :set_client
  before_action :ensure_client!
  before_action :set_ad_cost, only: %i[edit update destroy]

  def index
    @ad_costs = @client.ad_costs.order(start_date: :desc)
  end

  def new
    @ad_cost = @client.ad_costs.new
  end

  def create
    @ad_cost = @client.ad_costs.new(ad_cost_params)
    if @ad_cost.save
      redirect_to ad_costs_path, notice: 'Custo cadastrado com sucesso.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @ad_cost.update(ad_cost_params)
      redirect_to ad_costs_path, notice: 'Custo atualizado com sucesso.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @ad_cost.destroy
    redirect_to ad_costs_path, notice: 'Custo removido com sucesso.'
  end

  private

  def ensure_client!
    return if @client

    redirect_to crm_path, alert: 'Nenhum cliente selecionado.'
  end

  def set_ad_cost
    @ad_cost = @client.ad_costs.find(params[:id])
  end

  def ad_cost_params
    params.require(:ad_cost).permit(:platform, :name, :start_date, :end_date, :amount)
  end
end
