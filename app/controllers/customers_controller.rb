class CustomersController < ApplicationController
  before_action :set_filter_scope, only: [:index, :export_xlsx]

  def index
    @customers = @customers_scope.with_orders_count
                                 .includes(orders: { order_items: :product })
                                 .order(created_at: :desc)
                                 .paginate(page: params[:page], per_page: params_per_page(params[:per_page]))
  end

  def details
    customer = Customer.find(params[:id])

    orders = customer.orders
                     .includes(order_items: :product)
                     .order(shopify_creation_date: :desc)

    render json: {
      customer: {
        id: customer.id,
        name: [customer.first_name, customer.last_name].compact.join(' '),
        email: customer.email,
        phone: customer.phone,
        shopify_id: customer.shopify_customer_id,
        created_at: customer.created_at.strftime('%d/%m/%Y %H:%M')
      },
      orders: orders.map do |o|
        items = o.order_items

        {
          number: o.shopify_order_number,
          shopify_id: o.shopify_order_id,
          date: o.shopify_creation_date&.strftime('%d/%m/%Y %H:%M'),
          total: items.sum { |i| i.price.to_f * i.quantity.to_i },
          items_count: items.size,
          items: items.map do |i|
            {
              name: i.product&.shopify_product_name || i.sku,
              sku: i.sku,
              qty: i.quantity,
              price: i.price,
              image: i.product&.image_url
            }
          end
        }
      end
    }
  end

  def export_xlsx
    customers = @customers_scope
                  .with_orders_count
                  .order(created_at: :desc)

    workbook  = RubyXL::Workbook.new
    worksheet = workbook[0]
    worksheet.sheet_name = 'Clientes'

    headers = ['ID', 'Nome', 'E-mail', 'Telefone', 'ID Shopify', 'Cadastrado em', 'Total de Pedidos']
    headers.each_with_index { |h, i| worksheet.add_cell(0, i, h) }

    row = 1

    customers.each do |c|
      full_name = [c.first_name, c.last_name].compact.join(' ').presence || c.name.presence || ''

      worksheet.add_cell(row, 0, c.id)
      worksheet.add_cell(row, 1, full_name)
      worksheet.add_cell(row, 2, c.email.to_s)
      worksheet.add_cell(row, 3, c.phone.to_s)
      worksheet.add_cell(row, 4, c.shopify_customer_id.to_s)
      worksheet.add_cell(row, 5, c.created_at.strftime('%d/%m/%Y %H:%M'))
      worksheet.add_cell(row, 6, c.orders_count.to_i)

      row += 1
    end

    file_path = Rails.root.join('tmp', "customers_#{SecureRandom.hex(4)}.xlsx")
    workbook.write(file_path.to_s)

    send_file file_path,
              filename: "clientes_#{Time.current.strftime('%Y%m%d_%H%M')}.xlsx",
              type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
              disposition: 'attachment'
  end

  private

  def set_filter_scope
    @customers_scope = Customer.all

    @customers_scope = @customers_scope.search(params[:search]) if params[:search].present?

    @customers_scope = @customers_scope.phone_like(params[:phone]) if params[:phone].present?

    if params[:inactive_days].present?
      @customers_scope = @customers_scope.inactive_days(params[:inactive_days])
    end

    if params[:min_orders].present?
      @customers_scope = @customers_scope.with_min_orders(params[:min_orders])
    end

    if params[:product_name].present?
      @customers_scope = @customers_scope.bought_product(params[:product_name])
    end

    if params[:maderite].present?
      @customers_scope = @customers_scope.maderite
    end
  end
end