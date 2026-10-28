module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    # Mesmo login do Devise (cookie de sessão): websocket só pra quem está logado.
    def connect
      self.current_user = env['warden'].user(:user) || reject_unauthorized_connection
    end
  end
end
