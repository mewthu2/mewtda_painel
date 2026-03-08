class Shopify::Orders
  require 'shopify_api'
  extend ApplicationHelper

  class << self

    def sync_shopify_orders_to_rails(session:, limit: 100, status: 'any', time_range: :all)
      client = ShopifyAPI::Clients::Rest::Admin.new(session: session)

      total = 0

      created_at_min =
        case time_range.to_sym
        when :last_3_days
          3.days.ago.iso8601
        when :last_3_hours
          3.hours.ago.iso8601
        else
          nil
        end

      query_params = {
        limit: limit,
        status: status,
        fields: 'id,name,created_at,line_items,note_attributes,customer'
      }

      query_params[:created_at_min] = created_at_min if created_at_min.present?

      @henrri_location ||= Location.find_by!(slug: 'henrri')

      response = client.get(
        path: 'orders',
        query: query_params
      )

      loop do
        response.body['orders'].each do |shopify_order|
          create_or_update_order_from_shopify(
            shopify_order,
            session: session
          )
          total += 1
        end

        break unless response.next_page_info

        response = client.get(
          path: 'orders',
          query: {
            page_info: response.next_page_info
          }
        )
      end
    end

    def create_or_update_order_from_shopify(shopify_order, session:)
      shopify_order_id     = shopify_order['id'].to_s
      shopify_order_number = shopify_order['name']
      shopify_created_at   = Time.parse(shopify_order['created_at'])

      note_attributes = extract_note_attributes_from_hash(
        shopify_order['note_attributes']
      )

      staff_id   = note_attributes['staff_ID']
      staff_name = note_attributes['staff_name']

      location = @henrri_location ||= Location.find_by!(slug: 'henrri')

      customer = find_or_create_customer_from_shopify(
        shopify_order,
        session: session
      )

      order = Order.find_or_initialize_by(
        shopify_order_id: shopify_order_id
      )

      order.assign_attributes(
        shopify_order_number: shopify_order_number,
        staff_id: staff_id.presence || order.staff_id,
        staff_name: staff_name.presence || order.staff_name,
        location_id: location.id,
        shopify_creation_date: shopify_created_at,
        customer_id: customer&.id
      )

      order.created_at = shopify_created_at if order.new_record?
      order.updated_at = Time.current

      order.save! if order.changed?

      existing_items = order.order_items.index_by(&:sku)

      Array(shopify_order['line_items']).each do |line_item|
        sku = line_item['sku']
        next if sku.blank?

        price    = line_item['price'].to_f
        quantity = line_item['quantity'].to_i

        item = existing_items[sku]

        if item
          if item.price != price || item.quantity != quantity
            item.update!(
              price: price,
              quantity: quantity
            )
          end
        else
          product = Product.find_by(sku: sku)

          order.order_items.create!(
            product_id: product&.id,
            sku: sku,
            price: price,
            quantity: quantity,
            canceled: false
          )
        end
      rescue StandardError => e
        Rails.logger.error "[Shopify::Orders] Erro ao processar item SKU #{sku}: #{e.message}"
        next
      end

      order
    end

    def extract_note_attributes_from_hash(note_attributes_array)
      return {} unless note_attributes_array.is_a?(Array)

      note_attributes_array.each_with_object({}) do |attr, hash|
        hash[attr['name']] = attr['value']
      end
    end

    def find_or_create_customer_from_shopify(shopify_order, session:)
      customer_stub = shopify_order['customer']
      return nil unless customer_stub

      shopify_customer_id = customer_stub['id'].to_s

      client = ShopifyAPI::Clients::Rest::Admin.new(session: session)

      response = client.get(
        path: "customers/#{shopify_customer_id}.json"
      )

      shopify_customer = response.body['customer']
      return nil unless shopify_customer

      customer = Customer.find_or_initialize_by(
        shopify_customer_id: shopify_customer_id
      )

      assign_full_customer_data(customer, shopify_customer)

      customer.save! if customer.changed?

      customer
    end

    def assign_full_customer_data(customer, shopify_customer)
      data = shopify_customer.respond_to?(:as_json) ? shopify_customer.as_json : shopify_customer

      default_address = data['default_address'] || {}

      customer.assign_attributes(
        first_name: data['first_name'],
        last_name: data['last_name'],
        email: data['email'],
        phone: data['phone'],
        currency: data['currency'],
        tags: data['tags'],
        orders_count: data['orders_count'],
        total_spent: data['total_spent'],
        verified_email: data['verified_email'],
        tax_exempt: data['tax_exempt'],
        shopify_created_at: data['created_at'],
        shopify_updated_at: data['updated_at']
      )

      return unless default_address.present?

      customer.assign_attributes(
        default_address_name: default_address['name'],
        default_address_company: default_address['company'],
        default_address_phone: default_address['phone'],
        default_address_address1: default_address['address1'],
        default_address_address2: default_address['address2'],
        default_address_city: default_address['city'],
        default_address_province: default_address['province'],
        default_address_country: default_address['country'],
        default_address_zip: default_address['zip'],
        default_address_country_code: default_address['country_code'],
        default_address_province_code: default_address['province_code']
      )
    end

  end
end