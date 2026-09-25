class ExchangeConfigsController < ApplicationController
  include ClientScoped

  EMAIL_KINDS = %w[requested approved rejected completed].freeze

  before_action :set_client
  before_action :ensure_client!
  before_action :load_exchange_config

  def edit; end

  def email_templates; end

  def update
    @exchange_config.logo.purge if params.dig(:exchange_config, :remove_logo) == '1'
    EMAIL_KINDS.each do |kind|
      next unless params.dig(:exchange_config, :"remove_#{kind}_email_image") == '1'

      @exchange_config.public_send(:"#{kind}_email_image").purge
    end
    return_view = params[:return_to] == 'email_templates' ? :email_templates : :edit

    if @exchange_config.update(exchange_config_params)
      redirect_path = return_view == :email_templates ? email_templates_exchange_config_path : edit_exchange_config_path
      redirect_to redirect_path, notice: 'Configuração salva com sucesso.'
    else
      render return_view, status: :unprocessable_entity
    end
  end

  private

  def ensure_client!
    redirect_to crm_path, alert: 'Nenhum cliente selecionado.' unless @client
  end

  def load_exchange_config
    @exchange_config = @client.exchange_config || @client.build_exchange_config
  end

  def exchange_config_params
    params.require(:exchange_config).permit(
      :active, :company_name, :accent_color, :instructions, :return_window_days, :coupon_validity_days, :logo,
      :requested_email_subject, :requested_email_body, :requested_email_image,
      :approved_email_subject, :approved_email_body, :approved_email_image,
      :rejected_email_subject, :rejected_email_body, :rejected_email_image,
      :completed_email_subject, :completed_email_body, :completed_email_image
    )
  end
end
