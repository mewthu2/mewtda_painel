class SettingsController < ApplicationController
  before_action :set_client

  def edit; end

  def update
    params[:client].delete(:meta_access_token) if params[:client][:meta_access_token].blank?

    if @client.update(client_params)
      redirect_to edit_settings_path, notice: 'Configurações atualizadas com sucesso.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_client
    @client = current_user.client

    unless @client
      redirect_to crm_path, alert: 'Você não está vinculado a nenhum cliente.'
    end
  end

  def client_params
    params.require(:client).permit(
      :name, :email, :shopify_shop_url, :shopify_access_token,
      :zapi_instance_id, :zapi_instance_token, :zapi_client_token,
      :meta_access_token, :meta_ad_account_id,
      :google_ads_customer_id
    )
  end
end
