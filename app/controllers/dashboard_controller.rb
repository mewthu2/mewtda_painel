class DashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :set_client
  before_action :load_form_references, only: [:index]

  def index; end

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

  def set_client
    @is_admin = current_user.admin?

    if @is_admin
      @clients = Client.where(active: true).order(:name)
      @client = params[:client_id].present? ? Client.find_by(id: params[:client_id]) : @clients.first
    else
      @client = current_user.client
    end

    @selected_client_id = @client&.id
  end

  def load_form_references
    @period = params[:period].presence || "1"

    unless @client
      @empty_state = true
      @empty_message = @is_admin ? "Nenhum cliente cadastrado no sistema." : "Voce nao esta vinculado a nenhum cliente."
      return
    end

    range = case @period
      when "7"  then 7.days.ago..Time.current
      when "15" then 15.days.ago..Time.current
      when "30" then 30.days.ago..Time.current
      else           Time.current.beginning_of_day..Time.current
    end

    days_count = { "7" => 7, "15" => 15, "30" => 30 }[@period] || 1
    prev_range = (range.first - days_count.days)..(range.first - 1.second)

    base_scope = ShopifyEvent.where(client_id: @client.id, created_at: range)
    prev_scope = ShopifyEvent.where(client_id: @client.id, created_at: prev_range)

    # ══════════════════════════════════════════════════════════════
    # CONTAGENS DO FUNIL (uma unica query)
    # ══════════════════════════════════════════════════════════════
    counts_query = base_scope
      .where(kind: %w[page_viewed product_viewed product_added_to_cart checkout_started checkout_completed])
      .group(:kind)
      .count

    @counts = {
      page_viewed:        counts_query["page_viewed"] || 0,
      product_viewed:     counts_query["product_viewed"] || 0,
      added_to_cart:      counts_query["product_added_to_cart"] || 0,
      checkout_started:   counts_query["checkout_started"] || 0,
      checkout_completed: counts_query["checkout_completed"] || 0
    }

    prev_counts_query = prev_scope
      .where(kind: %w[page_viewed product_viewed product_added_to_cart checkout_started checkout_completed])
      .group(:kind)
      .count

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
      product_viewed:     page.zero? ? 0 : (@counts[:product_viewed]     / page * 100).round(2),
      added_to_cart:      page.zero? ? 0 : (@counts[:added_to_cart]      / page * 100).round(2),
      checkout_started:   page.zero? ? 0 : (@counts[:checkout_started]   / page * 100).round(2),
      checkout_completed: page.zero? ? 0 : (@counts[:checkout_completed] / page * 100).round(2)
    }

    @dropoff = {
      page_to_product:  @counts[:page_viewed] > 0 ? (100 - (@counts[:product_viewed].to_f / @counts[:page_viewed] * 100)).round(1) : 0,
      product_to_cart:  @counts[:product_viewed] > 0 ? (100 - (@counts[:added_to_cart].to_f / @counts[:product_viewed] * 100)).round(1) : 0,
      cart_to_checkout: @counts[:added_to_cart] > 0 ? (100 - (@counts[:checkout_completed].to_f / @counts[:added_to_cart] * 100)).round(1) : 0
    }

    # ══════════════════════════════════════════════════════════════
    # SESSOES UNICAS
    # ══════════════════════════════════════════════════════════════
    @unique_sessions = base_scope.distinct.count(:session_id)
    @prev_unique_sessions = prev_scope.distinct.count(:session_id)

    # ══════════════════════════════════════════════════════════════
    # SESSOES NAO CONVERTIDAS (sem checkout_completed)
    # ══════════════════════════════════════════════════════════════
    sessions_with_checkout = base_scope.where(kind: "checkout_completed").distinct.count(:session_id)
    @abandoned_carts = @unique_sessions - sessions_with_checkout
    @abandoned_rate = @unique_sessions > 0 ? ((@abandoned_carts.to_f / @unique_sessions) * 100).round(1) : 0

    # ══════════════════════════════════════════════════════════════
    # DISPOSITIVOS
    # ══════════════════════════════════════════════════════════════
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

    # ══════════════════════════════════════════════════════════════
    # TOP PRODUTOS
    # ══════════════════════════════════════════════════════════════
    @top_products_viewed = fetch_top_products(base_scope, "product_viewed")
    @top_products_carted = fetch_top_products(base_scope, "product_added_to_cart")

    # ══════════════════════════════════════════════════════════════
    # EVENTOS POR HORA (ajustado para horario local -3h)
    # ══════════════════════════════════════════════════════════════
    hourly_query = base_scope
      .group("EXTRACT(HOUR FROM created_at - INTERVAL '3 hours')::int")
      .count

    @hourly_events = (0..23).map { |h| [h, hourly_query[h] || 0] }.to_h

    # ══════════════════════════════════════════════════════════════
    # EVENTOS POR DIA DA SEMANA (ajustado para horario local -3h)
    # ══════════════════════════════════════════════════════════════
    weekday_query = base_scope
      .group("EXTRACT(DOW FROM created_at - INTERVAL '3 hours')::int")
      .count

    weekday_names = { 0 => "Dom", 1 => "Seg", 2 => "Ter", 3 => "Qua", 4 => "Qui", 5 => "Sex", 6 => "Sab" }
    @weekday_events = weekday_names.map { |k, v| { day: v, count: weekday_query[k] || 0 } }

    # ══════════════════════════════════════════════════════════════
    # ORIGENS DE TRAFEGO
    # ══════════════════════════════════════════════════════════════
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
          when /google/i    then "Google"
          when /facebook|fb/i then "Facebook"
          when /instagram/i then "Instagram"
          when /tiktok/i    then "TikTok"
          when /youtube/i   then "YouTube"
          when /twitter|x\.com/i then "Twitter/X"
          when /bing/i      then "Bing"
          when /pinterest/i then "Pinterest"
          when "", nil      then "Direto"
          else host.truncate(20)
        end
        @referrers[source] += 1
      end
    @referrers = @referrers.sort_by { |_, v| -v }.first(6).to_h

    # ══════════════════════════════════════════════════════════════
    # TEMPO MEDIO ENTRE ETAPAS
    # ══════════════════════════════════════════════════════════════
    @avg_times = calculate_avg_times(base_scope)

    # ══════════════════════════════════════════════════════════════
    # GRAFICO POR DIA (ajustado para horario local -3h)
    # ══════════════════════════════════════════════════════════════
    @daily_events = base_scope
      .where(kind: %w[page_viewed product_viewed product_added_to_cart checkout_completed])
      .group("DATE(created_at - INTERVAL '3 hours')", :kind)
      .count

    # ══════════════════════════════════════════════════════════════
    # SESSOES AGRUPADAS
    # ══════════════════════════════════════════════════════════════
    @sessions = fetch_sessions(base_scope)
  end

  # ══════════════════════════════════════════════════════════════
  # HELPERS
  # ══════════════════════════════════════════════════════════════

  def fetch_top_products(scope, kind)
    results = scope
      .where(kind: kind)
      .select(
        "data->'productVariant'->'product'->>'id' as product_id",
        "data->'productVariant'->'product'->>'title' as product_title",
        "data->'productVariant'->'product'->>'url' as product_url",
        "data->'productVariant'->'image'->>'src' as product_image",
        "data->'productVariant'->'price'->>'amount' as product_price",
        "data->'productVariant'->'price'->>'currencyCode' as currency",
        "COUNT(*) as view_count"
      )
      .group(
        "data->'productVariant'->'product'->>'id'",
        "data->'productVariant'->'product'->>'title'",
        "data->'productVariant'->'product'->>'url'",
        "data->'productVariant'->'image'->>'src'",
        "data->'productVariant'->'price'->>'amount'",
        "data->'productVariant'->'price'->>'currencyCode'"
      )
      .order("view_count DESC")
      .limit(5)

    results.map do |r|
      {
        id:       r.product_id,
        title:    r.product_title || "Produto ##{r.product_id}",
        url:      r.product_url,
        image:    r.product_image,
        price:    r.product_price&.to_f,
        currency: r.currency || "BRL",
        count:    r.view_count.to_i
      }
    end
  end

  def calculate_avg_times(scope)
    sample_sessions = scope
      .where(kind: "checkout_completed")
      .distinct
      .limit(50)
      .pluck(:session_id)

    return { page_to_product: 0, product_to_cart: 0, cart_to_checkout: 0 } if sample_sessions.empty?

    events_by_session = scope
      .where(session_id: sample_sessions)
      .where(kind: %w[page_viewed product_viewed product_added_to_cart checkout_completed])
      .order(:session_id, :created_at)
      .pluck(:session_id, :kind, :created_at)
      .group_by(&:first)

    times = { page_to_product: [], product_to_cart: [], cart_to_checkout: [] }

    events_by_session.each do |_, events|
      timestamps = {}
      events.each do |_, kind, created_at|
        timestamps[kind] ||= created_at
      end

      if timestamps["page_viewed"] && timestamps["product_viewed"]
        diff = (timestamps["product_viewed"] - timestamps["page_viewed"]) / 60.0
        times[:page_to_product] << diff if diff > 0 && diff < 60
      end
      if timestamps["product_viewed"] && timestamps["product_added_to_cart"]
        diff = (timestamps["product_added_to_cart"] - timestamps["product_viewed"]) / 60.0
        times[:product_to_cart] << diff if diff > 0 && diff < 60
      end
      if timestamps["product_added_to_cart"] && timestamps["checkout_completed"]
        diff = (timestamps["checkout_completed"] - timestamps["product_added_to_cart"]) / 60.0
        times[:cart_to_checkout] << diff if diff > 0 && diff < 120
      end
    end

    {
      page_to_product:  times[:page_to_product].any? ? (times[:page_to_product].sum / times[:page_to_product].size).round(1) : 0,
      product_to_cart:  times[:product_to_cart].any? ? (times[:product_to_cart].sum / times[:product_to_cart].size).round(1) : 0,
      cart_to_checkout: times[:cart_to_checkout].any? ? (times[:cart_to_checkout].sum / times[:cart_to_checkout].size).round(1) : 0
    }
  end

  def fetch_sessions(scope)
    # Busca sessoes recentes com agregacao
    session_ids = scope
      .group(:session_id)
      .order(Arel.sql("MAX(created_at) DESC"))
      .limit(20)
      .pluck(:session_id)

    return [] if session_ids.empty?

    # Busca dados agregados para cada sessao em uma query
    session_data = scope
      .where(session_id: session_ids)
      .group(:session_id)
      .select(
        :session_id,
        "MIN(created_at) as started_at",
        "MAX(created_at) as last_at",
        "COUNT(*) as event_count",
        "MIN(shop_domain) as shop_domain",
        "BOOL_OR(kind = 'checkout_completed') as has_checkout"
      )

    # Busca os kinds de cada sessao separadamente
    kinds_data = scope
      .where(session_id: session_ids)
      .order(created_at: :desc)
      .pluck(:session_id, :kind)
      .group_by(&:first)
      .transform_values { |v| v.map(&:last).first(5) }

    # Busca o navigator de cada sessao
    nav_data = scope
      .where(session_id: session_ids)
      .where("context->>'navigator' IS NOT NULL")
      .order(:session_id, :created_at)
      .select("DISTINCT ON (session_id) session_id, context->>'navigator' as nav")
      .each_with_object({}) { |r, h| h[r.session_id] = r.nav }

    session_data.order(Arel.sql("MAX(created_at) DESC")).map do |s|
      ua = JSON.parse(nav_data[s.session_id])["userAgent"] rescue nil
      device = if ua =~ /Mobile|iPhone|Android.*Mobile/i
        "mobile"
      elsif ua =~ /iPad|Tablet/i
        "tablet"
      else
        "desktop"
      end

      duration = s.last_at && s.started_at ? ((s.last_at - s.started_at) / 60.0).round(1) : 0

      {
        session_id:   s.session_id,
        shop_domain:  s.shop_domain,
        started_at:   s.started_at,
        last_at:      s.last_at,
        event_count:  s.event_count,
        last_kinds:   kinds_data[s.session_id] || [],
        abandoned:    !s.has_checkout,
        device:       device,
        duration_min: duration
      }
    end
  end
end