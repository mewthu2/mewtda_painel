module SalesDashboardHelper
  def currency(value)
    number_to_currency(value, unit: 'R$', separator: ',', delimiter: '.')
  end

  def month_label(date)
    names = %w[janeiro fevereiro março abril maio junho julho agosto setembro outubro novembro dezembro]
    "#{names[date.month - 1]}/#{date.year}"
  end

  SESSIONS_DISCLAIMER = 'A Shopify não disponibiliza sessões/conversão via API — este número vem do nosso ' \
                        'pixel de rastreamento próprio e pode não bater exatamente com o relatório nativo ' \
                        'da Shopify.'.freeze

  # Ícone de alerta com tooltip explicando que Acessos/Taxa de Conversão vêm
  # do pixel próprio (a Shopify não expõe sessões/conversão via API).
  def sessions_disclaimer_icon
    content_tag(:i, '', class: 'fa-solid fa-triangle-exclamation sd-disclaimer-icon', title: SESSIONS_DISCLAIMER)
  end
end
