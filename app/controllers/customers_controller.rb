class CustomersController < ApplicationController
  before_action :load_form_references, only: [:index]
  before_action :set_filter_scope, only: [:index, :export_xlsx]

  def index
    @customers = @customers_scope
                   .order(created_at: :desc)
                   .paginate(page: params[:page], per_page: params_per_page(params[:per_page]))
  end

  def export_xlsx
    customers = @customers_scope.order(created_at: :desc)

    workbook  = RubyXL::Workbook.new
    worksheet = workbook[0]
    worksheet.sheet_name = 'Clientes'

    headers = ['ID', 'Nome', 'E-mail', 'Telefone', 'ID Shopify', 'Cadastrado em', 'Total de Pedidos']
    headers.each_with_index { |h, i| worksheet.add_cell(0, i, h) }

    row = 1
    customers.each do |c|
      full_name    = [c.first_name, c.last_name].compact.join(' ').presence || c.name.presence || ''
      total_orders = Order.where(customer_id: c.id).count
      worksheet.add_cell(row, 0, c.id)
      worksheet.add_cell(row, 1, full_name)
      worksheet.add_cell(row, 2, c.email.to_s)
      worksheet.add_cell(row, 3, c.phone.to_s)
      worksheet.add_cell(row, 4, c.shopify_customer_id.to_s)
      worksheet.add_cell(row, 5, c.created_at.strftime('%d/%m/%Y %H:%M'))
      worksheet.add_cell(row, 6, total_orders)
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

    if params[:search].present?
      @customers_scope = @customers_scope.where(
        'first_name ILIKE ? OR last_name ILIKE ? OR email ILIKE ?',
        "%#{params[:search]}%", "%#{params[:search]}%", "%#{params[:search]}%"
      )
    end

    @customers_scope = @customers_scope.where('phone ILIKE ?', "%#{params[:phone]}%") if params[:phone].present?

    if params[:inactive_days].present?
      days   = params[:inactive_days].to_i
      cutoff = days.days.ago
      active_ids = Order.where('created_at >= ?', cutoff).pluck(:customer_id).uniq
      @customers_scope = @customers_scope.where.not(id: active_ids)
    end

    if params[:min_orders].present?
      min          = params[:min_orders].to_i
      customer_ids = Order.group(:customer_id).having('COUNT(*) >= ?', min).pluck(:customer_id)
      @customers_scope = @customers_scope.where(id: customer_ids)
    end

    # Filtro por produto — usa shopify_product_name em OrderItem (sem shopify_product_id)
    if params[:product_name].present?
      order_ids    = OrderItem.where('name ILIKE ?', "%#{params[:product_name]}%").pluck(:order_id).uniq
      customer_ids = Order.where(id: order_ids).pluck(:customer_id).uniq
      @customers_scope = @customers_scope.where(id: customer_ids)
    end

    # Coleção Maderite — via order_items.name que contém o nome do produto
    if params[:maderite].present?
      maderite_names = Product.where('tags ILIKE ?', '%maderite%').pluck(:shopify_product_name)
      if maderite_names.any?
        conditions = maderite_names.map { |n| OrderItem.sanitize_sql_like(n) }
        order_ids  = OrderItem.where(
          maderite_names.map { 'name ILIKE ?' }.join(' OR '),
          *maderite_names.map { |n| "%#{n}%" }
        ).pluck(:order_id).uniq
        customer_ids = Order.where(id: order_ids).pluck(:customer_id).uniq
        @customers_scope = @customers_scope.where(id: customer_ids)
      else
        @customers_scope = @customers_scope.none
      end
    end
  end

  def load_form_references; end
end
