class OrdersController < ApplicationController
  before_action :load_form_references, only: [:index]
  before_action :set_filter_scope, only: [:index, :export_xlsx]

  def index
    @orders = @orders_scope
                .order(shopify_creation_date: :desc)
                .paginate(page: params[:page], per_page: params_per_page(params[:per_page]))
  end

  def export_xlsx
    orders = @orders_scope.order(shopify_creation_date: :desc)

    workbook  = RubyXL::Workbook.new
    worksheet = workbook[0]
    worksheet.sheet_name = 'Pedidos'

    headers = ['ID', 'Nº Pedido', 'ID Shopify', 'Cliente', 'Telefone', 'Itens', 'Total (R$)', 'Data']
    headers.each_with_index { |h, i| worksheet.add_cell(0, i, h) }

    row = 1
    orders.each do |o|
      customer   = o.try(:customer)
      full_name  = customer ? [customer.first_name, customer.last_name].compact.join(' ').presence || customer.name.to_s : ''
      phone      = customer&.phone.to_s
      items      = o.try(:order_items).presence || []
      total      = items.sum { |i| i.price.to_f * i.quantity.to_i }

      worksheet.add_cell(row, 0, o.id)
      worksheet.add_cell(row, 1, o.shopify_order_number.to_s)
      worksheet.add_cell(row, 2, o.shopify_order_id.to_s)
      worksheet.add_cell(row, 3, full_name)
      worksheet.add_cell(row, 4, phone)
      worksheet.add_cell(row, 5, items.size)
      worksheet.add_cell(row, 6, total.round(2))
      worksheet.add_cell(row, 7, o.shopify_creation_date&.strftime('%d/%m/%Y %H:%M').to_s)
      row += 1
    end

    file_path = Rails.root.join('tmp', "orders_#{SecureRandom.hex(4)}.xlsx")
    workbook.write(file_path.to_s)

    send_file file_path,
              filename: "pedidos_#{Time.current.strftime('%Y%m%d_%H%M')}.xlsx",
              type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
              disposition: 'attachment'
  end

  private

  def set_filter_scope
    @orders_scope = Order.all
    @orders_scope = @orders_scope.where(kinds: params[:kinds])                                             if params[:kinds].present?
    @orders_scope = @orders_scope.where(staff_name: params[:staff_name])                                   if params[:staff_name].present?
    @orders_scope = @orders_scope.where('shopify_order_number ILIKE ?', "%#{params[:search]}%")            if params[:search].present?
    @orders_scope = @orders_scope.where('shopify_creation_date >= ?', params[:date_from].to_date)          if params[:date_from].present?
    @orders_scope = @orders_scope.where('shopify_creation_date <= ?', params[:date_to].to_date.end_of_day) if params[:date_to].present?
  end

  def load_form_references
    @kinds       = Order.distinct.pluck(:kinds).compact.sort
    @staff_names = Order.distinct.pluck(:staff_name).compact.sort
  end
end
