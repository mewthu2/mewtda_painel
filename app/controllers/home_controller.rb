class HomeController < ApplicationController
  include ClientScoped

  skip_before_action :authenticate_user!, only: [:index]
  before_action :set_client, if: :user_signed_in?, only: [:index]
  before_action :load_sales_preview, if: -> { user_signed_in? && @client }, only: [:index]

  def index
    render user_signed_in? ? 'home/dashboard' : 'home/index'
  end

  private

  def load_sales_preview
    today = Date.current
    @sales = Sales::DailyBreakdown.new(client: @client, year: today.year, month: today.month).call
  end
end
