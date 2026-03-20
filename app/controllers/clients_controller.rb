class ClientsController < ApplicationController
  before_action :authenticate_user!

  def update_selected_client
    unless current_user.admin?
      return render json: { success: false, error: 'Não autorizado' }, status: :forbidden
    end

    client = Client.find_by(id: params[:client_id], active: true)

    if client
      session[:selected_client_id] = client.id
      render json: { success: true, client_name: client.name }
    else
      render json: { success: false, error: 'Cliente não encontrado' }, status: :not_found
    end
  end
end
