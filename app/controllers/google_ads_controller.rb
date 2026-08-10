class GoogleAdsController < ApplicationController
  before_action :set_client, only: [:connect, :disconnect]
  before_action :authorize_client_owner!, only: [:connect, :disconnect]

  AUTH_URL = 'https://accounts.google.com/o/oauth2/v2/auth'.freeze
  TOKEN_URL = 'https://oauth2.googleapis.com/token'.freeze
  SCOPE = 'https://www.googleapis.com/auth/adwords'.freeze
  STATE_EXPIRY = 15.minutes

  def connect
    state = verifier.generate(@client.id, expires_in: STATE_EXPIRY)

    redirect_to "#{AUTH_URL}?#{connect_params(state).to_query}", allow_other_host: true
  end

  def callback
    client_id = verifier.verify(params[:state])
    client = Client.find(client_id)

    unless authorized_for?(client)
      return redirect_to root_path, alert: 'Acesso restrito.'
    end

    response = HTTParty.post(
      TOKEN_URL,
      body: {
        client_id: ENV['GOOGLE_ADS_CLIENT_ID'],
        client_secret: ENV['GOOGLE_ADS_CLIENT_SECRET'],
        code: params[:code],
        grant_type: 'authorization_code',
        redirect_uri: google_ads_callback_url
      }
    )

    unless response.success? && response.parsed_response['refresh_token'].present?
      return redirect_to settings_return_path(client), alert: 'Não foi possível conectar ao Google Ads.'
    end

    client.update!(
      google_ads_refresh_token: response.parsed_response['refresh_token'],
      google_ads_connected_at: Time.current
    )

    redirect_to settings_return_path(client), notice: 'Google Ads conectado com sucesso.'
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
    redirect_to clients_path, alert: 'Estado inválido na conexão com o Google Ads.'
  end

  def disconnect
    @client.update!(google_ads_refresh_token: nil, google_ads_connected_at: nil)
    redirect_to settings_return_path(@client), notice: 'Google Ads desconectado.'
  end

  private

  def set_client
    @client = Client.find(params[:id])
  end

  def authorize_client_owner!
    return if authorized_for?(@client)

    redirect_to root_path, alert: 'Acesso restrito.'
  end

  def authorized_for?(client)
    current_user.admin? || current_user.client_id == client.id
  end

  def settings_return_path(client)
    current_user.admin? ? edit_client_path(client) : edit_settings_path
  end

  def connect_params(state)
    {
      client_id: ENV['GOOGLE_ADS_CLIENT_ID'],
      redirect_uri: google_ads_callback_url,
      response_type: 'code',
      scope: SCOPE,
      access_type: 'offline',
      prompt: 'consent',
      state: state
    }
  end

  def verifier
    Rails.application.message_verifier(:google_ads_oauth_state)
  end
end
