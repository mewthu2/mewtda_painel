require 'rubyXL/convenience_methods'

module CustomAutomations
  # Planilha .xlsx de conferência da nota de transferência: aba "Itens" com uma
  # linha por SKU e aba "Resumo" com os parâmetros da execução.
  class TransferNoteSpreadsheet
    HEADERS = ['SKU', 'Descrição (Tiny)', 'Produto na Shopify', 'Quantidade', 'Preço médio praticado',
               '% aplicado', 'Valor unitário NF', 'Total NF', 'NCM', 'GTIN', 'No Tiny da matriz?',
               'Pedidos'].freeze

    def initialize(run)
      @run = run
    end

    def filename
      "nota-transferencia-#{@run.period_start.strftime('%Y-%m-%d')}-a-#{@run.period_end.strftime('%Y-%m-%d')}.xlsx"
    end

    def to_xlsx
      workbook = RubyXL::Workbook.new
      write_items(workbook[0])
      write_summary(workbook.add_worksheet('Resumo'))
      workbook.stream.string
    end

    private

    def write_items(sheet)
      sheet.sheet_name = 'Itens'
      HEADERS.each_with_index do |header, col|
        sheet.add_cell(0, col, header)
        sheet[0][col].change_font_bold(true)
      end

      @run.items.each_with_index do |item, index|
        row = index + 1
        [item['sku'], item['description'], item['shopify_title'], item['quantity'], item['average_price'],
         @run.price_percentage.to_f, item['unit_value'], item['total'], item['ncm'], item['gtin'],
         item['tiny_found'] ? 'Sim' : 'Não', item['orders_count']].each_with_index do |value, col|
          sheet.add_cell(row, col, value)
        end
      end

      total_row = @run.items.size + 1
      sheet.add_cell(total_row, 0, 'TOTAL').change_font_bold(true)
      sheet.add_cell(total_row, 3, @run.total_quantity).change_font_bold(true)
      sheet.add_cell(total_row, 7, @run.total_value.to_f).change_font_bold(true)
    end

    def write_summary(sheet)
      rows = [
        ['Período', "#{@run.period_start.strftime('%d/%m/%Y')} a #{@run.period_end.strftime('%d/%m/%Y')}"],
        ['Pedidos considerados', @run.orders_count],
        ['Filtro de pedidos', @run.order_filter_label],
        ['% sobre o preço praticado', @run.price_percentage.to_f],
        ['Itens (SKUs)', @run.items.size],
        ['Quantidade total', @run.total_quantity],
        ['Valor total da nota', @run.total_value.to_f],
        ['ID da nota no Tiny', @run.tiny_note_id],
        ['Número da nota', @run.tiny_note_number],
        ['Situação', @run.status_label]
      ]
      rows += @run.warnings.map { |w| ['Atenção', w] }

      rows.each_with_index do |(label, value), row|
        sheet.add_cell(row, 0, label).change_font_bold(true)
        sheet.add_cell(row, 1, value)
      end
    end
  end
end
