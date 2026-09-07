module Widget
  class PopupController < ApplicationController
    skip_before_action :authenticate_user!, :redirect_affiliate_to_events!
    protect_from_forgery with: :null_session

    before_action :set_popup

    def show_config
      if @popup&.active?
        render json: {
          active: true,
          title: @popup.title,
          description: @popup.description,
          button_text: @popup.button_text,
          accent_color: @popup.accent_color,
          template: @popup.template,
          size: @popup.size,
          reappear_after_hours: @popup.reappear_after_hours,
          image_url: @popup.image.attached? ? url_for(@popup.image) : nil
        }
      else
        render json: { active: false }
      end
    end

    def create_submission
      return render json: { error: 'not_found' }, status: :not_found unless @popup&.active?

      name = params[:name].to_s.strip
      email = params[:email].to_s.strip
      phone = params[:phone].to_s.strip

      if name.blank? || email.blank?
        return render json: { error: 'invalid' }, status: :unprocessable_entity
      end

      result = Shopify::CreateCustomer.new(@popup.client).call(name: name, email: email, phone: phone)

      PopupSubmission.create!(
        popup: @popup, name: name, email: email, phone: phone,
        shopify_customer_id: result[:customer_id],
        status: result[:ok] ? 'success' : 'shopify_error'
      )

      render json: { coupon_code: @popup.coupon_code }
    end

    private

    def set_popup
      @popup = Popup.find_by(public_token: params[:token])
    end
  end
end
