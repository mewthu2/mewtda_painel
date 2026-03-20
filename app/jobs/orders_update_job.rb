class OrdersUpdateJob < ApplicationJob
  queue_as :default

  def perform(action:, client_id:, **options)
    @client = Client.find(client_id)
    
    unless @client.active?
      Rails.logger.warn "[OrdersUpdateJob] Client #{client_id} está inativo. Ignorando job."
      return
    end

    case action
    when 'sync_all'
      sync_all_orders(options)
    when 'sync_single'
      sync_single_order(options)
    when 'update_staff'
      update_staff(options)
    when 'sync_shopify_orders_routine'
      sync_shopify_orders_routine(options)
    when 'sync_customers_from_orders'
      sync_customers_from_orders(options)
    else
      Rails.logger.error "[OrdersUpdateJob] Ação desconhecida: #{action}"
    end
  rescue StandardError => e
    Rails.logger.error "[OrdersUpdateJob] Erro para client #{client_id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise e
  end

  def sync_all_orders(options)
    limit  = options[:limit] || 100
    status = options[:status] || 'any'

    session = build_shopify_session

    Shopify::Orders.sync_shopify_orders_to_rails(
      session: session,
      client: @client,
      limit: limit,
      status: status,
      time_range: :all
    )
  end

  def sync_shopify_orders_routine(options)
    limit   = options[:limit] || 250
    status  = options[:status] || 'any'
    routine = options[:routine] || :last_3_hours

    session = build_shopify_session

    Shopify::Orders.sync_shopify_orders_to_rails(
      session: session,
      client: @client,
      limit: limit,
      status: status,
      time_range: routine
    )

    sync_customers_from_orders(batch_size: 50)
  end

  def sync_single_order(options)
    shopify_order_id = options[:shopify_order_id]
    raise ArgumentError, 'shopify_order_id é obrigatório' if shopify_order_id.blank?

    session = build_shopify_session
    client_api = ShopifyAPI::Clients::Rest::Admin.new(session: session)

    response = client_api.get(
      path: "orders/#{shopify_order_id}.json",
      query: {
        fields: 'id,created_at,line_items,note_attributes,customer'
      }
    )

    shopify_order = response.body['order']
    return unless shopify_order

    Shopify::Orders.create_or_update_order_from_shopify(
      shopify_order,
      session: session,
      client: @client
    )
  end

  def update_staff(options)
    shopify_order_id = options[:shopify_order_id]
    raise ArgumentError, 'shopify_order_id é obrigatório' if shopify_order_id.blank?

    Shopify::Orders.update_order_staff(
      shopify_order_id,
      staff_id: options[:staff_id],
      staff_name: options[:staff_name]
    )
  end

  def sync_customers_from_orders(options)
    batch_size = options[:batch_size] || 50

    session = build_shopify_session

    # Filtra apenas orders do client atual
    Order.where(client_id: @client.id)
         .where.not(shopify_order_id: nil)
         .where(customer_id: nil)
         .find_in_batches(batch_size: batch_size) do |orders|
      orders.each do |order|
        sync_customer_for_order(order, session)
      rescue StandardError => e
        Rails.logger.error "[OrdersUpdateJob] Erro no order #{order.id}: #{e.message}"
      end
    end
  end

  private

  def build_shopify_session
    ShopifyAPI::Auth::Session.new(
      shop: @client.shopify_shop_url,
      access_token: @client.shopify_access_token
    )
  end

  def sync_customer_for_order(order, session)
    return if order.shopify_order_id.blank?

    client_api = ShopifyAPI::Clients::Rest::Admin.new(session:)

    response = client_api.get(
      path: "orders/#{order.shopify_order_id}.json",
      query: { fields: 'id,customer' }
    )

    shopify_order = response.body['order']
    return unless shopify_order && shopify_order['customer']

    shopify_customer = shopify_order['customer']

    customer = Customer.find_or_initialize_by(
      shopify_customer_id: shopify_customer['id'].to_s
    )

    Shopify::Orders.assign_full_customer_data(customer, shopify_customer)

    customer.save! if customer.changed?

    order.update!(customer_id: customer.id)

    Rails.logger.info "[OrdersUpdateJob] Order #{order.id} atualizado com customer #{customer.id}"
  end
end
