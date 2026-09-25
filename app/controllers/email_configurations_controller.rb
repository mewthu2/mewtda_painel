class EmailConfigurationsController < ApplicationController
  include ClientScoped

  before_action :set_client
  before_action :require_client!

  def edit; end

  def update
    if current_client.update(domain_params)
      Ses::DomainIdentityService.new(current_client).create! if current_client.email_sending_domain.present?
      redirect_to edit_email_configuration_path,
                  notice: 'Domínio salvo. Cadastre os registros de DNS abaixo pra concluir a verificação.'
    else
      render :edit, status: :unprocessable_entity
    end
  rescue Aws::Errors::ServiceError => e
    redirect_to edit_email_configuration_path, alert: "Erro ao configurar o domínio na AWS: #{e.message}"
  end

  def refresh_status
    verified = Ses::DomainIdentityService.new(current_client).refresh_status!
    notice = verified ? 'Domínio verificado com sucesso!' : 'Ainda não verificado — confira os registros de DNS.'
    redirect_to edit_email_configuration_path, notice: notice
  rescue Aws::Errors::ServiceError => e
    redirect_to edit_email_configuration_path, alert: "Erro ao verificar o domínio: #{e.message}"
  end

  private

  def current_client
    @client
  end
  helper_method :current_client

  def require_client!
    redirect_to crm_path, alert: 'Nenhum cliente selecionado.' unless @client
  end

  def domain_params
    params.require(:client).permit(:email_sending_domain)
  end
end
