# Cria um cupom de desconto (percentual ou valor fixo) na Shopify pro cliente
# informado. Diferente de Shopify::CreateCashbackDiscount (que usa credenciais
# fixas de um único cliente via ENV — um bug pré-existente), este serviço usa
# sempre as credenciais do `client` passado, funcionando pra qualquer loja.
class Shopify::CreateDiscountCode
  def self.call(client:, title:, percentage: nil, amount: nil, customer_shopify_id: nil, expires_in: 7.days)
    session = ShopifyAPI::Auth::Session.new(shop: client.shopify_shop_url, access_token: client.shopify_access_token)
    api_client = ShopifyAPI::Clients::Rest::Admin.new(session: session)

    code = "REC#{SecureRandom.alphanumeric(8).upcase}"
    starts_at = Time.current
    ends_at = starts_at + expires_in

    customer_selection = if customer_shopify_id.present?
                           { customers: { add: [customer_shopify_id] } }
                         else
                           { all: true }
                         end

    value = if amount.present?
              { discountAmount: { amount: amount.to_f, appliesOnEachItem: false } }
            else
              { percentage: percentage.to_f / 100 }
            end

    mutation = <<~GRAPHQL
      mutation discountCodeBasicCreate($basicCodeDiscount: DiscountCodeBasicInput!) {
        discountCodeBasicCreate(basicCodeDiscount: $basicCodeDiscount) {
          codeDiscountNode {
            id
            codeDiscount {
              ... on DiscountCodeBasic {
                codes(first: 1) { nodes { code } }
              }
            }
          }
          userErrors { field message }
        }
      }
    GRAPHQL

    variables = {
      basicCodeDiscount: {
        title: title,
        code: code,
        startsAt: starts_at.iso8601,
        endsAt: ends_at.iso8601,
        customerGets: { value: value, items: { all: true } },
        customerSelection: customer_selection,
        usageLimit: 1
      }
    }

    response = api_client.post(path: 'graphql.json', body: { query: mutation, variables: variables })
    errors = response.body.dig('data', 'discountCodeBasicCreate', 'userErrors')

    return nil if errors.present? && errors.any?

    code
  end
end
