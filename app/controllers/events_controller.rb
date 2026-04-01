class EventsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_client
  before_action :load_analytics, only: [:index]

  def index; end

  def generate_link
    url   = params[:url].to_s.strip
    code  = params[:utm_code].to_s.strip

    if url.blank? || code.blank?
      return render json: { error: "URL e utm_code sao obrigatorios" }, status: :unprocessable_entity
    end

    begin
      uri = URI.parse(url)

      unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
        return render json: { error: "URL invalida. Use http:// ou https://" }, status: :unprocessable_entity
      end

      existing = URI.decode_www_form(uri.query || "").to_h
      existing["utm_affiliate"] = code

      uri.query = URI.encode_www_form(existing)

      render json: { link: uri.to_s }
    rescue URI::InvalidURIError
      render json: { error: "URL invalida." }, status: :unprocessable_entity
    end
  end

  def session_detail
    return render json: { error: 'Sem cliente' }, status: :unprocessable_entity unless @client

    events = ShopifyEvent
      .where(client_id: @client.id, session_id: params[:session_id])
      .order(:created_at)

    render json: {
      session_id:  params[:session_id],
      shop_domain: events.first&.shop_domain,
      started_at:  events.first&.created_at,
      last_at:     events.last&.created_at,
      event_count: events.count,
      events: events.map do |e|
        {
          id:         e.id,
          kind:       e.kind,
          event_name: e.event_name,
          event_type: e.event_type,
          event_id:   e.event_id,
          created_at: e.created_at,
          data:       e.data,
          context:    e.context
        }
      end
    }
  end

  private

  def current_client
    @current_client ||= current_user.client
  end
  helper_method :current_client

  def set_client
    @client = current_client

    unless @client
      @empty_state = true
      @empty_message = "Voce nao esta vinculado a nenhum cliente."
    end
  end

  def load_analytics
    @period = params[:period].presence || "1"
    @filter_year = params[:year].presence&.to_i
    @filter_month = params[:month].presence&.to_i
    @utm_code = params[:utm_code].presence

    unless @client
      @empty_state = true
      return
    end

    # Identifica o afiliado pelo utm_code quando presente
    if @utm_code.present?
      @affiliate = @client.users.where(profile_id: Profile::AFFILIATE, utm_code: @utm_code).first
    end

    # Filtro por mes/ano tem prioridade sobre os filtros rapidos
    if @filter_year.present? && @filter_month.present?
      start_date = Time.zone.local(@filter_year, @filter_month, 1).beginning_of_day
      end_date = start_date.end_of_month
      range = start_date..end_date
      # Periodo anterior = mes anterior completo
      prev_start = (start_date - 1.month).beginning_of_month
      prev_end = prev_start.end_of_month
      prev_range = prev_start..prev_end
      @using_month_filter = true
    else
      range = case @period
        when "7"  then 7.days.ago..Time.current
        when "15" then 15.days.ago..Time.current
        when "30" then 30.days.ago..Time.current
        else Time.current.beginning_of_day..Time.current
      end

      days_count = { "7" => 7, "15" => 15, "30" => 30 }[@period] || 1
      prev_range = (range.first - days_count.days)..(range.first - 1.second)
    end

    base_scope = ShopifyEvent.where(client_id: @client.id, created_at: range)
    prev_scope = ShopifyEvent.where(client_id: @client.id, created_at: prev_range)

    # Se vier utm_code, filtra apenas eventos dessa tag de afiliado
    if @utm_code.present?
      utm_pattern = "%utm_affiliate=#{@utm_code}%"
      base_scope = base_scope.where(
        "context->'document'->'location'->>'search' ILIKE :p OR context->'document'->'location'->>'href' ILIKE :p",
        p: utm_pattern
      )
      prev_scope = prev_scope.where(
        "context->'document'->'location'->>'search' ILIKE :p OR context->'document'->'location'->>'href' ILIKE :p",
        p: utm_pattern
      )
    end

    funnel_kinds = %w[page_viewed product_viewed product_added_to_cart checkout_started checkout_completed]

    counts_query = base_scope.where(kind: funnel_kinds).group(:kind).count
    prev_counts_query = prev_scope.where(kind: funnel_kinds).group(:kind).count

    @counts = {
      page_viewed:        counts_query["page_viewed"] || 0,
      product_viewed:     counts_query["product_viewed"] || 0,
      added_to_cart:      counts_query["product_added_to_cart"] || 0,
      checkout_started:   counts_query["checkout_started"] || 0,
      checkout_completed: counts_query["checkout_completed"] || 0
    }

    @prev_counts = {
      page_viewed:        prev_counts_query["page_viewed"] || 0,
      product_viewed:     prev_counts_query["product_viewed"] || 0,
      added_to_cart:      prev_counts_query["product_added_to_cart"] || 0,
      checkout_started:   prev_counts_query["checkout_started"] || 0,
      checkout_completed: prev_counts_query["checkout_completed"] || 0
    }

    if @counts.values.sum.zero? && @prev_counts.values.sum.zero?
      @empty_state = true
      @empty_message = "Nenhum evento encontrado para #{@client.name} no periodo selecionado."
      return
    end

    @empty_state = false

    page = @counts[:page_viewed].to_f

    @conversion = {
      product_viewed:     page.zero? ? 0 : (@counts[:product_viewed] / page * 100).round(2),
      added_to_cart:      page.zero? ? 0 : (@counts[:added_to_cart] / page * 100).round(2),
      checkout_started:   page.zero? ? 0 : (@counts[:checkout_started] / page * 100).round(2),
      checkout_completed: page.zero? ? 0 : (@counts[:checkout_completed] / page * 100).round(2)
    }

    @dropoff = {
      page_to_product:  @counts[:page_viewed] > 0 ? (100 - (@counts[:product_viewed].to_f / @counts[:page_viewed] * 100)).round(1) : 0,
      product_to_cart:  @counts[:product_viewed] > 0 ? (100 - (@counts[:added_to_cart].to_f / @counts[:product_viewed] * 100)).round(1) : 0,
      cart_to_checkout: @counts[:added_to_cart] > 0 ? (100 - (@counts[:checkout_completed].to_f / @counts[:added_to_cart] * 100)).round(1) : 0
    }

    @unique_sessions = base_scope.distinct.count(:session_id)
    @prev_unique_sessions = prev_scope.distinct.count(:session_id)

    sessions_with_checkout = base_scope.where(kind: "checkout_completed").distinct.count(:session_id)
    @abandoned_carts = @unique_sessions - sessions_with_checkout
    @abandoned_rate = @unique_sessions > 0 ? ((@abandoned_carts.to_f / @unique_sessions) * 100).round(1) : 0

    @devices = { mobile: 0, desktop: 0, tablet: 0 }
    base_scope
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

    @top_products_viewed = fetch_top_products(base_scope, "product_viewed")
    @top_products_carted = fetch_top_products(base_scope, "product_added_to_cart")

    hourly_query = base_scope
      .group("EXTRACT(HOUR FROM created_at - INTERVAL '3 hours')::int")
      .count

    @hourly_events = (0..23).map { |h| [h, hourly_query[h] || 0] }.to_h

    weekday_query = base_scope
      .group("EXTRACT(DOW FROM created_at - INTERVAL '3 hours')::int")
      .count

    weekday_names = { 0 => "Dom", 1 => "Seg", 2 => "Ter", 3 => "Qua", 4 => "Qui", 5 => "Sex", 6 => "Sab" }
    @weekday_events = weekday_names.map { |k, v| { day: v, count: weekday_query[k] || 0 } }

    @referrers = Hash.new(0)
    base_scope
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
          when /twitter|x\.com/i  then "Twitter/X"
          when /bing/i            then "Bing"
          when /pinterest/i       then "Pinterest"
          when "", nil            then "Direto"
          else host.truncate(20)
        end
        @referrers[source] += 1
      end
    @referrers = @referrers.sort_by { |_, v| -v }.first(6).to_h

    @avg_times = calculate_avg_times(@client.id, range)

    @daily_events = base_scope
      .where(kind: %w[page_viewed product_viewed product_added_to_cart checkout_completed])
      .group("DATE(created_at - INTERVAL '3 hours')", :kind)
      .count

    @sessions = fetch_sessions(@client.id, range, @utm_code)
  end

  def fetch_top_products(scope, kind)
    product_id_path =
      if kind == "product_added_to_cart"
        "data->'cartLine'->'merchandise'->'product'->>'id'"
      else
        "data->'productVariant'->'product'->>'id'"
      end

    counts = scope.where(kind: kind)
                  .where("#{product_id_path} IS NOT NULL")
                  .group(Arel.sql(product_id_path))
                  .order(Arel.sql('COUNT(*) DESC'))
                  .limit(10)
                  .count

    return [] if counts.empty?

    event_data = scope.where(kind: kind)
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

      if kind == "product_added_to_cart"
        variant_data = payload.dig("cartLine", "merchandise") || {}
        product_data = variant_data.dig("product") || {}
        image_src = variant_data.dig("image", "src")
        price = variant_data.dig("price", "amount")&.to_f
      else
        variant_data = payload.dig("productVariant") || {}
        product_data = variant_data.dig("product") || {}
        image_src = variant_data.dig("image", "src")
        price = variant_data.dig("price", "amount")&.to_f
      end

      title = product&.shopify_product_name ||
              product_data["title"] ||
              variant_data["title"] ||
              (variant_data["sku"].present? ? "SKU: #{variant_data["sku"]}" : nil) ||
              (product_id.present? ? "ID #{product_id}" : "Produto")

      image = product&.image_url || image_src
      sku = variant_data["sku"]

      {
        id:    product_id,
        title: title,
        sku:   sku,
        image: image,
        price: product&.price || price,
        count: count
      }
    end
  end

  def calculate_avg_times(client_id, range)
    sql = <<-SQL
      SELECT
        session_id,
        MIN(CASE WHEN kind = 'page_viewed' THEN created_at END) as page_time,
        MIN(CASE WHEN kind = 'product_viewed' THEN created_at END) as product_time,
        MIN(CASE WHEN kind = 'product_added_to_cart' THEN created_at END) as cart_time,
        MIN(CASE WHEN kind = 'checkout_completed' THEN created_at END) as checkout_time
      FROM shopify_events
      WHERE client_id = :client_id
        AND created_at BETWEEN :start_at AND :end_at
        AND kind IN ('page_viewed', 'product_viewed', 'product_added_to_cart', 'checkout_completed')
      GROUP BY session_id
    SQL

    results = ShopifyEvent.find_by_sql([sql, { client_id: client_id, start_at: range.first, end_at: range.last }])

    times = { page_to_product: [], product_to_cart: [], cart_to_checkout: [] }

    results.each do |row|
      page_time = row[:page_time]
      product_time = row[:product_time]
      cart_time = row[:cart_time]
      checkout_time = row[:checkout_time]

      times[:page_to_product] << ((product_time - page_time) / 60).round(1) if page_time && product_time
      times[:product_to_cart] << ((cart_time - product_time) / 60).round(1) if product_time && cart_time
      times[:cart_to_checkout] << ((checkout_time - cart_time) / 60).round(1) if cart_time && checkout_time
    end

    {
      page_to_product:  times[:page_to_product].any? ? (times[:page_to_product].sum / times[:page_to_product].size).round(1) : 0,
      product_to_cart:  times[:product_to_cart].any? ? (times[:product_to_cart].sum / times[:product_to_cart].size).round(1) : 0,
      cart_to_checkout: times[:cart_to_checkout].any? ? (times[:cart_to_checkout].sum / times[:cart_to_checkout].size).round(1) : 0
    }
  end

  def fetch_sessions(client_id, range, utm_code = nil)
    # Constrói a cláusula WHERE com filtro opcional de utm_code
    utm_filter = ""
    if utm_code.present?
      utm_filter = "AND (context->'document'->'location'->>'search' ILIKE '%utm_affiliate=#{utm_code}%' 
                        OR context->'document'->'location'->>'href' ILIKE '%utm_affiliate=#{utm_code}%')"
    end

    sql = <<-SQL
      SELECT
        session_id,
        MIN(created_at) as started_at,
        MAX(created_at) as last_at,
        COUNT(*) as event_count,
        ARRAY_AGG(DISTINCT kind ORDER BY kind) as kinds_arr,
        (SELECT shop_domain FROM shopify_events e2
         WHERE e2.session_id = shopify_events.session_id
           AND e2.client_id = :client_id
           AND e2.created_at BETWEEN :start_at AND :end_at
           #{utm_filter}
         ORDER BY e2.created_at ASC LIMIT 1) as shop_domain,
        (SELECT context->>'navigator' FROM shopify_events e3
         WHERE e3.session_id = shopify_events.session_id
           AND e3.client_id = :client_id
           AND e3.created_at BETWEEN :start_at AND :end_at
           #{utm_filter}
         ORDER BY e3.created_at ASC LIMIT 1) as first_context
      FROM shopify_events
      WHERE client_id = :client_id
        AND created_at BETWEEN :start_at AND :end_at
        #{utm_filter}
      GROUP BY session_id
      ORDER BY MAX(created_at) DESC
      LIMIT 50
    SQL

    results = ShopifyEvent.find_by_sql([sql, { client_id: client_id, start_at: range.first, end_at: range.last }])

    results.map do |row|
      ua = begin
        ctx = row[:first_context].is_a?(String) ? JSON.parse(row[:first_context]) : row[:first_context]
        ctx["userAgent"] || ""
      rescue
        ""
      end

      device = if ua =~ /Mobile|Android.*Mobile|iPhone|iPod/i
        "Mobile"
      elsif ua =~ /iPad|Android(?!.*Mobile)|Tablet/i
        "Tablet"
      else
        "Desktop"
      end

      kinds = row[:kinds_arr] || []
      abandoned = !kinds.include?("checkout_completed")
      started_at = row[:started_at]
      last_at = row[:last_at]

      {
        session_id:   row[:session_id],
        shop_domain:  row[:shop_domain],
        started_at:   started_at,
        last_at:      last_at,
        duration_min: started_at && last_at ? ((last_at - started_at) / 60).round(1) : 0,
        event_count:  row[:event_count].to_i,
        last_kinds:   kinds.last(4),
        device:       device,
        abandoned:    abandoned
      }
    end
  end
end
