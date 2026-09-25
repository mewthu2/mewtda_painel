class ExchangeRequestsController < ApplicationController
  include ClientScoped

  before_action :set_client
  before_action :ensure_client!
  before_action :set_exchange_request, only: %i[show update]

  def index
    scope = @client.exchange_requests.includes(:exchange_request_items).order(created_at: :desc)
    @status_filter = params[:status].presence
    @exchange_requests = @status_filter.present? ? scope.where(status: @status_filter) : scope
  end

  def show; end

  def update
    case params[:status]
    when 'approved'
      Exchange::Approve.new(@exchange_request).call
    when 'rejected'
      @exchange_request.update!(status: :rejected)
      SendExchangeEmailJob.perform_later(exchange_request_id: @exchange_request.id, kind: 'rejected')
    when 'completed'
      @exchange_request.update!(status: :completed)
      SendExchangeEmailJob.perform_later(exchange_request_id: @exchange_request.id, kind: 'completed')
    end

    @exchange_request.update!(internal_notes: params[:internal_notes]) if params[:internal_notes].present?

    redirect_to exchange_request_path(@exchange_request), notice: 'Solicitação atualizada.'
  end

  private

  def ensure_client!
    redirect_to crm_path, alert: 'Nenhum cliente selecionado.' unless @client
  end

  def set_exchange_request
    @exchange_request = @client.exchange_requests.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to exchange_requests_path, alert: 'Solicitação não encontrada.'
  end
end
