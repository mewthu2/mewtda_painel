class LandingPagesController < ApplicationController
  include ClientScoped

  before_action :set_client
  before_action :require_client!
  before_action :set_landing_page, only: %i[show edit update destroy]

  def index
    @landing_pages = current_client.landing_pages.order(created_at: :desc)
    @leads_count = LandingPageLead.where(landing_page: @landing_pages).group(:landing_page_id).count
    orders = Order.where(landing_page: @landing_pages, cancelled_at: nil).group(:landing_page_id)
    @orders_count = orders.count
    @orders_revenue = orders.sum(:total_price)
  end

  def show
    @leads = @landing_page.leads.order(created_at: :desc)
    @orders = @landing_page.attributed_orders.includes(:customer).order(shopify_creation_date: :desc)
    @revenue = @orders.sum(:total_price)
  end

  def new
    @landing_page = current_client.landing_pages.new(path_prefix: current_client.slug)
  end

  def create
    @landing_page = current_client.landing_pages.new(landing_page_params)
    if @landing_page.save
      redirect_to landing_page_path(@landing_page), notice: 'Landing page criada com sucesso.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @landing_page.update(landing_page_params)
      redirect_to landing_page_path(@landing_page), notice: 'Landing page atualizada com sucesso.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @landing_page.destroy
    redirect_to landing_pages_path, notice: 'Landing page excluída com sucesso.'
  end

  private

  def current_client
    @client
  end
  helper_method :current_client

  def require_client!
    return if @client

    redirect_to crm_path, alert: 'Nenhum cliente selecionado.'
  end

  def set_landing_page
    @landing_page = current_client.landing_pages.find(params[:id])
  end

  def landing_page_params
    params.require(:landing_page).permit(:name, :path_prefix, :slug, :template, :active, :ends_at, 
:product_handles_text)
  end
end
