class HomeController < ApplicationController
  include ClientScoped

  skip_before_action :authenticate_user!, only: [:index, :sites, :app_page, :crm_page, :trocas_page]
  before_action :set_client, if: :user_signed_in?, only: [:index]
  before_action :load_sales_preview, if: -> { user_signed_in? && @client }, only: [:index]

  def index
    render user_signed_in? ? 'home/dashboard' : 'home/index'
  end

  # Página pública do produto "Sua Loja" (criação de sites Shopify)
  def sites; end

  # Página pública do produto "App" (app iOS/Android da loja — em breve)
  def app_page; end

  # Página pública do produto "MeuCRM"
  def crm_page; end

  # Página pública do produto "Quero Trocar"
  def trocas_page; end

  private

  def load_sales_preview
    today = Date.current
    @sales = Sales::DailyBreakdown.new(client: @client, year: today.year, month: today.month).call
    @metrics = Sales::MonthlyMetrics.new(client: @client, year: today.year, month: today.month).call
  end
end
