module SalesDashboardHelper
  def currency(value)
    number_to_currency(value, unit: 'R$', separator: ',', delimiter: '.')
  end

  def month_label(date)
    names = %w[janeiro fevereiro março abril maio junho julho agosto setembro outubro novembro dezembro]
    "#{names[date.month - 1]}/#{date.year}"
  end
end
