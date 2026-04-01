class AffiliatesController < ApplicationController
  before_action :authenticate_user!
  before_action :require_client!
  before_action :set_affiliate, only: %i[show edit update destroy]
  before_action :load_analytics, only: [:show]

  AFFILIATE_PROFILE_ID = Profile::AFFILIATE

  def index
    @affiliates = current_client.users
                                .where(profile_id: AFFILIATE_PROFILE_ID)
                                .order(created_at: :desc)
                                .paginate(page: params[:page], per_page: params_per_page(params[:per_page]))

    if params[:search].present?
      search_term = "%#{params[:search]}%"
      @affiliates = @affiliates.where(
        'users.name ILIKE ? OR users.email ILIKE ? OR users.utm_code ILIKE ? OR users.discount_code ILIKE ?',
        search_term, search_term, search_term, search_term
      )
    end

    if params[:status].present?
      case params[:status]
      when 'active'
        @affiliates = @affiliates.where(active: true) if column_exists?(:users, :active)
      when 'inactive'
        @affiliates = @affiliates.where(active: false) if column_exists?(:users, :active)
      end
    end
  end

  def show; end

  def new
    @affiliate = User.new
  end

  def create
    @affiliate = User.new(affiliate_params)
    @affiliate.client = current_client
    @affiliate.profile_id = AFFILIATE_PROFILE_ID
    @affiliate.password = generate_temporary_password if @affiliate.password.blank?

    if @affiliate.save
      redirect_to affiliates_path, notice: 'Afiliado criado com sucesso.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    update_params = affiliate_params
    
    # Remove password params if blank (keeps existing password)
    if update_params[:password].blank?
      update_params.delete(:password)
      update_params.delete(:password_confirmation)
    end

    if @affiliate.update(update_params)
      redirect_to affiliates_path, notice: 'Afiliado atualizado com sucesso.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @affiliate.destroy
    redirect_to affiliates_path, notice: 'Afiliado excluído com sucesso.'
  end

  private

  def current_client
    @current_client ||= current_user.client
  end
  helper_method :current_client

  def require_client!
    unless current_client.present?
      redirect_to root_path, alert: 'Você precisa estar vinculado a um cliente para acessar afiliados.'
    end
  end

  def set_affiliate
    @affiliate = current_client.users.where(profile_id: AFFILIATE_PROFILE_ID).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to affiliates_path, alert: 'Afiliado não encontrado.'
  end

  def affiliate_params
    params.require(:user).permit(:name, :email, :phone, :utm_code, :discount_code, :password, :password_confirmation)
  end

  def generate_temporary_password
    SecureRandom.hex(8)
  end

  def column_exists?(table, column)
    ActiveRecord::Base.connection.column_exists?(table, column)
  end

  # ===== ANALYTICS DO AFILIADO =====
  def load_analytics
    return unless @affiliate&.utm_code.present?

    @period = params[:period].presence || "30"
    
    range = case @period
      when "7"  then 7.days.ago..Time.current
      when "15" then 15.days.ago..Time.current
      when "30" then 30.days.ago..Time.current
      when "90" then 90.days.ago..Time.current
      else 30.days.ago..Time.current
    end

    # Busca eventos que contenham utm_affiliate no context.document.location.search ou href
    utm_pattern = "%utm_affiliate=#{@affiliate.utm_code}%"
    
    @base_scope = ShopifyEvent
      .where(client_id: current_client.id, created_at: range)
      .where("context->'document'->'location'->>'search' ILIKE ? OR context->'document'->'location'->>'href' ILIKE ?", utm_pattern, utm_pattern)

    # KPIs principais
    @total_events = @base_scope.count
    @unique_sessions = @base_scope.distinct.count(:session_id)
    
    # Contagem por tipo de evento
    @event_counts = @base_scope.group(:kind).count
    
    @counts = {
      page_viewed:        @event_counts["page_viewed"] || 0,
      product_viewed:     @event_counts["product_viewed"] || 0,
      added_to_cart:      @event_counts["product_added_to_cart"] || 0,
      checkout_started:   @event_counts["checkout_started"] || 0,
      checkout_completed: @event_counts["checkout_completed"] || 0
    }

    # Taxas de conversão
    page = @counts[:page_viewed].to_f
    @conversion = {
      product_viewed:     page.zero? ? 0 : (@counts[:product_viewed] / page * 100).round(2),
      added_to_cart:      page.zero? ? 0 : (@counts[:added_to_cart] / page * 100).round(2),
      checkout_completed: page.zero? ? 0 : (@counts[:checkout_completed] / page * 100).round(2)
    }

    # Top produtos visitados pelo tráfego do afiliado
    @top_products = fetch_affiliate_top_products(@base_scope)

    # Dispositivos
    @devices = { mobile: 0, desktop: 0, tablet: 0 }
    @base_scope
      .select("DISTINCT ON (session_id) session_id, context->>'navigator' as nav")
      .order(:session_id, :created_at)
      .each do |row|
        ua = JSON.parse(row.nav)["userAgent"] rescue nil
        next unless ua
        if ua =~ /Mobile|Android.*Mobile|iPhone|iPod/i
          @devices[:mobile] += 1
        elsif ua =~ /iPad|Android(?!.*Mobile)|Tablet/i
          @devices[:tablet] += 1
        else
          @devices[:desktop] += 1
        end
      end

    # Referrers
    @referrers = Hash.new(0)
    @base_scope
      .where(kind: "page_viewed")
      .where("context->'document'->>'referrer' IS NOT NULL AND context->'document'->>'referrer' != ''")
      .select("DISTINCT ON (session_id) session_id, context->'document'->>'referrer' as ref")
      .order(:session_id, :created_at)
      .each do |row|
        ref = row.ref
        next if ref.blank?
        begin
          host = URI.parse(ref).host&.gsub(/^www\./, '') || "direto"
        rescue
          host = "outro"
        end
        source = case host
          when /google/i          then "Google"
          when /facebook|fb/i     then "Facebook"
          when /instagram/i       then "Instagram"
          when /tiktok/i          then "TikTok"
          when /youtube/i         then "YouTube"
          else host.truncate(20)
        end
        @referrers[source] += 1
      end
    @referrers = @referrers.sort_by { |_, v| -v }.first(5).to_h

    # Eventos por hora
    hourly_query = @base_scope
      .group("EXTRACT(HOUR FROM created_at - INTERVAL '3 hours')::int")
      .count
    @hourly_events = (0..23).map { |h| [h, hourly_query[h] || 0] }.to_h

    # Sessões recentes do afiliado
    @recent_sessions = fetch_affiliate_sessions(@base_scope)
  end

  def fetch_affiliate_top_products(scope)
    product_id_path = "data->'productVariant'->'product'->>'id'"

    counts = scope.where(kind: "product_viewed")
                  .where("#{product_id_path} IS NOT NULL")
                  .group(Arel.sql(product_id_path))
                  .order(Arel.sql('COUNT(*) DESC'))
                  .limit(10)
                  .count

    return [] if counts.empty?

    event_data = scope.where(kind: "product_viewed")
                      .where("#{product_id_path} IN (?)", counts.keys.compact)
                      .select("DISTINCT ON (#{product_id_path}) #{product_id_path} AS product_id, data")
                      .order(Arel.sql("#{product_id_path}"))
                      .each_with_object({}) do |row, h|
                        h[row.product_id] = begin
                          row.data.is_a?(Hash) ? row.data : JSON.parse(row.data.to_s)
                        rescue
                          {}
                        end
                      end

    counts.map do |product_id, count|
      product = Product.find_by(shopify_product_id: product_id) rescue nil
      payload = event_data[product_id] || {}
      variant_data = payload.dig("productVariant") || {}
      product_data = variant_data.dig("product") || {}
      image_src = variant_data.dig("image", "src")
      price = variant_data.dig("price", "amount")&.to_f

      title = product&.shopify_product_name ||
              product_data["title"] ||
              variant_data["title"] ||
              (product_id.present? ? "ID #{product_id}" : "Produto")

      {
        id:    product_id,
        title: title,
        sku:   variant_data["sku"],
        image: product&.image_url || image_src,
        price: product&.price || price,
        count: count
      }
    end
  end

  def fetch_affiliate_sessions(scope)
    sql = <<-SQL
      SELECT
        session_id,
        MIN(created_at) as started_at,
        MAX(created_at) as last_at,
        COUNT(*) as event_count,
        ARRAY_AGG(DISTINCT kind ORDER BY kind) as kinds_arr
      FROM shopify_events
      WHERE id IN (#{scope.select(:id).to_sql})
      GROUP BY session_id
      ORDER BY MAX(created_at) DESC
      LIMIT 20
    SQL

    results = ShopifyEvent.find_by_sql(sql)

    results.map do |row|
      kinds = row[:kinds_arr] || []
      converted = kinds.include?("checkout_completed")
      started_at = row[:started_at]
      last_at = row[:last_at]

      {
        session_id:   row[:session_id],
        started_at:   started_at,
        last_at:      last_at,
        duration_min: started_at && last_at ? ((last_at - started_at) / 60).round(1) : 0,
        event_count:  row[:event_count].to_i,
        kinds:        kinds,
        converted:    converted
      }
    end
  end
end
