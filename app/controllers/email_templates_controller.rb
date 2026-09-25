class EmailTemplatesController < ApplicationController
  include ClientScoped

  before_action :set_client
  before_action :require_client!
  before_action :set_email_template, only: %i[edit update destroy]

  def index
    @email_templates = current_client.email_templates.order(created_at: :desc)
  end

  def new
    @email_template = current_client.email_templates.new(preset_attributes)
  end

  def create
    @email_template = current_client.email_templates.new(email_template_params)
    if @email_template.save
      redirect_to email_templates_path, notice: 'E-mail criado com sucesso.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    @email_template.image.purge if params.dig(:email_template, :remove_image) == '1'
    @email_template.image_bottom.purge if params.dig(:email_template, :remove_image_bottom) == '1'

    if @email_template.update(email_template_params)
      redirect_to email_templates_path, notice: 'E-mail atualizado com sucesso.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @email_template.destroy
    redirect_to email_templates_path, notice: 'E-mail excluído com sucesso.'
  end

  private

  def current_client
    @client
  end
  helper_method :current_client

  def require_client!
    redirect_to crm_path, alert: 'Nenhum cliente selecionado.' unless @client
  end

  def set_email_template
    @email_template = current_client.email_templates.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to email_templates_path, alert: 'E-mail não encontrado.'
  end

  def preset_attributes
    EmailTemplate.preset(params[:preset]) || {}
  end

  def email_template_params
    params.require(:email_template).permit(
      :name, :subject, :heading, :body, :button_text, :button_url, :coupon_code,
      :accent_color, :layout, :trigger_kind, :active, :image, :image_bottom,
      :trigger_delay_hours, :trigger_inactive_days, :trigger_days_after_purchase
    )
  end
end
