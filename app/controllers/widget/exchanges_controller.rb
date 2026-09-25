module Widget
  class ExchangesController < ApplicationController
    skip_before_action :authenticate_user!, :redirect_affiliate_to_events!
    protect_from_forgery with: :null_session

    before_action :set_config
    before_action :require_active_config!

    def new; end

    def lookup
      @order = find_order
      return render_not_found_error unless @order

      @eligibility = Exchange::EligibilityCalculator.new(@config).call(@order)
      @order_number = params[:order_number]
      @email = params[:email]
    end

    def create
      @order = find_order
      return render_not_found_error(view: :new) unless @order

      @eligibility = Exchange::EligibilityCalculator.new(@config).call(@order)
      @order_number = params[:order_number]
      @email = params[:email]
      selected_items = build_selected_items

      if selected_items.empty?
        flash.now[:alert] = 'Selecione ao menos um item elegível.'
        render :lookup, status: :unprocessable_entity
        return
      end

      exchange_request = nil

      ActiveRecord::Base.transaction do
        exchange_request = @config.client.exchange_requests.create!(
          shopify_order_id: @order[:id], shopify_order_number: @order[:number],
          customer_email: params[:email], customer_name: params[:customer_name]
        )
        selected_items.each { |item| exchange_request.exchange_request_items.create!(item) }
      end

      SendExchangeEmailJob.perform_later(exchange_request_id: exchange_request.id, kind: 'requested')
      NotifyExchangeRequestJob.perform_later(exchange_request_id: exchange_request.id)
      render :confirmation
    rescue ActiveRecord::RecordInvalid => e
      flash.now[:alert] = "Não foi possível enviar: #{e.record.errors.full_messages.to_sentence}"
      render :lookup, status: :unprocessable_entity
    end

    private

    def set_config
      @config = ExchangeConfig.find_by(slug: params[:token])
    end

    def require_active_config!
      render plain: 'Não encontrado', status: :not_found unless @config&.active?
    end

    def render_not_found_error(view: :new)
      flash.now[:alert] = 'Pedido não encontrado. Confira o número do pedido e o e-mail informados.'
      render view, status: :unprocessable_entity
    end

    def find_order
      return nil unless Exchange::LookupThrottle.new.allow?(request.remote_ip)

      Shopify::FindOrderForExchange.call(client: @config.client, order_number: params[:order_number], email: params[:email])
    end

    def build_selected_items
      allowed_kinds = @eligibility == :return_and_exchange ? %w[troca devolucao] : ['troca']

      Array(params[:items]).filter_map do |raw|
        raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
        source = @order[:items].find { |item| item[:sku] == raw['sku'] }
        next unless source
        next unless allowed_kinds.include?(raw['kind'])

        source.merge(kind: raw['kind'], reason: raw['reason'], photo: raw['photo'])
      end
    end
  end
end
