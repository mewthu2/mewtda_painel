class ProductsController < ApplicationController
  before_action :load_form_references, only: [:index]
  before_action :set_filter_scope, only: [:index, :export_xlsx]

  def index
    @products = @products_scope
                  .order(created_at: :desc)
                  .paginate(page: params[:page], per_page: params_per_page(params[:per_page]))
  end

  def export_xlsx
    products = @products_scope.order(created_at: :desc)

    workbook  = RubyXL::Workbook.new
    worksheet = workbook[0]
    worksheet.sheet_name = 'Produtos'

    headers = ['ID', 'SKU', 'Nome', 'Fornecedor', 'Cor/Variação 1', 'Tamanho/Variação 2', 'Variação 3', 'Preço (R$)', 'Custo (R$)', 'ID Shopify', 'Criado em']
    headers.each_with_index { |h, i| worksheet.add_cell(0, i, h) }

    row = 1
    products.each do |p|
      worksheet.add_cell(row, 0,  p.id)
      worksheet.add_cell(row, 1,  p.sku.to_s)
      worksheet.add_cell(row, 2,  p.shopify_product_name.to_s)
      worksheet.add_cell(row, 3,  p.vendor.to_s)
      worksheet.add_cell(row, 4,  p.option1.to_s)
      worksheet.add_cell(row, 5,  p.option2.to_s)
      worksheet.add_cell(row, 6,  p.option3.to_s)
      worksheet.add_cell(row, 7,  p.price.to_f.round(2))
      worksheet.add_cell(row, 8,  p.cost.to_f.round(2))
      worksheet.add_cell(row, 9,  p.shopify_product_id.to_s)
      worksheet.add_cell(row, 10, p.created_at.strftime('%d/%m/%Y %H:%M'))
      row += 1
    end

    file_path = Rails.root.join('tmp', "products_#{SecureRandom.hex(4)}.xlsx")
    workbook.write(file_path.to_s)

    send_file file_path,
              filename: "produtos_#{Time.current.strftime('%Y%m%d_%H%M')}.xlsx",
              type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
              disposition: 'attachment'
  end

  private

  def set_filter_scope
    @products_scope = Product.all
    @products_scope = @products_scope.where(vendor: params[:vendor])                                    if params[:vendor].present?
    @products_scope = @products_scope.where(option1: params[:option1])                                  if params[:option1].present?
    @products_scope = @products_scope.where(option2: params[:option2])                                  if params[:option2].present?
    @products_scope = @products_scope.where('shopify_product_name ILIKE ?', "%#{params[:search]}%")     if params[:search].present?
  end

  def load_form_references
    @vendors  = Product.distinct.pluck(:vendor).compact.sort
    @option1s = Product.distinct.pluck(:option1).compact.sort
    @option2s = Product.distinct.pluck(:option2).compact.sort
  end
end
