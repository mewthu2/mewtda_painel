class PublicLandingPagesController < ApplicationController
  skip_before_action :authenticate_user!, :redirect_affiliate_to_events!
  protect_from_forgery with: :null_session

  layout 'landing_page'

  before_action :set_landing_page

  def show
    LandingPage.update_counters(@landing_page.id, views_count: 1) unless @preview

    @client = @landing_page.client
    @storefront = Shopify::Storefront.new(@client)
    @products = @storefront.products(@landing_page.product_handles)

    render "landing_pages/templates/#{@landing_page.template}"
  end

  def lead
    # Honeypot: campo escondido que só robô preenche. Responde sucesso pra não dar pista.
    return render json: { ok: true } if params[:website].present?

    result = LandingPages::RegisterLead.new(@landing_page).call(
      name: params[:name], email: params[:email], phone: params[:phone],
      utms: params.permit(*LandingPageLead::UTM_FIELDS).to_h
    )

    if result.lead&.persisted?
      render json: { ok: true }
    else
      render json: { ok: false, errors: result.lead&.errors&.full_messages.to_a }, status: :unprocessable_entity
    end
  end

  # Alguém rompeu a corrente da página (animação do template). Conta uma vez
  # por navegador — o cookie assinado segura quem limpou o localStorage — e
  # não conta pré-visualização.
  def break_chain
    cookie = :"lp_broke_#{@landing_page.id}"

    unless @preview || cookies.signed[cookie]
      LandingPage.update_counters(@landing_page.id, chain_breaks_count: 1)
      cookies.permanent.signed[cookie] = { value: '1', httponly: true, same_site: :lax }
    end

    render json: { count: @landing_page.reload.chain_breaks_count }
  end

  private

  # Página inativa só abre pra quem está logado no painel e é dono (ou admin) —
  # serve de pré-visualização e não conta visita.
  def set_landing_page
    @landing_page = LandingPage.includes(:client).find_by(path_prefix: params[:path_prefix], slug: params[:slug])
    return not_found if @landing_page.nil? || LandingPage::RESERVED_PREFIXES.include?(params[:path_prefix])

    @preview = !@landing_page.active?
    not_found if @preview && !can_preview?
  end

  def can_preview?
    user_signed_in? && (current_user.admin? || current_user.client_id == @landing_page.client_id)
  end

  def not_found
    render file: Rails.public_path.join('404.html'), status: :not_found, layout: false
  end
end
