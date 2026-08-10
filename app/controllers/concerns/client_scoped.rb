module ClientScoped
  extend ActiveSupport::Concern

  private

  def current_client_id
    if current_user.admin?
      session[:selected_client_id] || current_user.client_id
    else
      current_user.client_id
    end
  end

  def set_client
    @client = Client.find_by(id: current_client_id)

    unless @client
      @empty_state = true
      @empty_message = current_user.admin? ? 'Nenhum cliente selecionado. Selecione um cliente no menu superior.' : 'Você não está vinculado a nenhum cliente.'
    end
  end
end
