class Shopify::CreateCashbackDiscount
  def self.call(order:)
    session =  ShopifyAPI::Auth::Session.new(
      shop: ENV.fetch('HENRRI_SHOP_URL'),
      access_token: ENV.fetch('HENRRI_OAUTH_SECRET')
    )

    client = ShopifyAPI::Clients::Rest::Admin.new(session:)

    coupon_code = GenerateCashbackCode.call(order.shopify_order_number)

    starts_at = order.shopify_creation_date
    ends_at = starts_at + 30.days

    mutation = <<~GRAPHQL
      mutation discountCodeBasicCreate($basicCodeDiscount: DiscountCodeBasicInput!) {
        discountCodeBasicCreate(basicCodeDiscount: $basicCodeDiscount) {
          codeDiscountNode {
            id
            codeDiscount {
              ... on DiscountCodeBasic {
                codes(first: 1) {
                  nodes {
                    code
                  }
                }
              }
            }
          }
          userErrors {
            field
            message
          }
        }
      }
    GRAPHQL

    variables = {
      basicCodeDiscount: {
        title: "Cashback 8% - Pedido #{order.shopify_order_number}",
        code: coupon_code,
        startsAt: starts_at.iso8601,
        endsAt: ends_at.iso8601,
        customerGets: {
          value: {
            percentage: 0.08
          },
          items: {
            all: true
          }
        },
        customerSelection: {
          customers: {
            add: [order.customer.shopify_customer_id]
          }
        },
        usageLimit: 1
      }
    }

    response = client.post(
      path: 'graphql.json',
      body: {
        query: mutation,
        variables:
      }
    )

    { coupon_code:, response: }
  end
end