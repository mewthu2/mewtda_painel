class PopupsController < ApplicationController
  include ClientScoped

  before_action :set_client
  before_action :ensure_client!
  before_action :load_popup

  def edit; end

  def update
    @popup.image.purge if params.dig(:popup, :remove_image) == '1'

    if @popup.update(popup_params)
      redirect_to edit_popup_path, notice: 'Pop-up salvo com sucesso.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def submissions
    @status_filter = params[:status].presence
    @popup_submissions =
      if @popup.persisted?
        scope = @popup.popup_submissions.includes(popup: :client).order(created_at: :desc)
        @status_filter.present? ? scope.where(status: @status_filter) : scope
      else
        PopupSubmission.none
      end
  end

  private

  def ensure_client!
    return if @client

    redirect_to crm_path, alert: 'Nenhum cliente selecionado.'
  end

  def load_popup
    @popup = @client.popup || @client.build_popup
  end

  def popup_params
    params.require(:popup).permit(
      :active, :title, :description, :coupon_code, :button_text, :accent_color,
      :template, :size, :reappear_after_hours, :image
    )
  end
end
