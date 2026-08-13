class ApplicationController < ActionController::Base
  include Common

  protect_from_forgery with: :exception

  before_action :authenticate_user!
  before_action :redirect_affiliate_to_events!

  layout 'layouts/application'

  private

  def require_admin!
    unless current_user&.admin?
      redirect_to crm_path, alert: 'Acesso restrito a administradores.'
    end
  end

  # Afiliados (profile_id == 3) só podem acessar events e generate_link
  def redirect_affiliate_to_events!
    return unless user_signed_in?

    return unless current_user.profile_id == Profile::AFFILIATE

    # NÃO roda para Devise (login, logout, etc)
    return if devise_controller?

    # Permite events; a home (logado) agora mostra prévia de vendas da loja,
    # que não é relevante para afiliados
    return if controller_name == 'events'

    redirect_to events_path(utm_code: current_user.utm_code)
  end
end