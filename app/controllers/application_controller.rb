class ApplicationController < ActionController::Base
  include Common

  before_action :authenticate_user!
  protect_from_forgery unless: -> { request.format.json? }

  layout 'layouts/application'

  private

  def require_admin!
    unless current_user&.admin?
      redirect_to root_path, alert: 'Acesso restrito a administradores.'
    end
  end
end
