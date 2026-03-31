class ProcessCashbackCampaignsJob < ApplicationJob
  queue_as :default

  def perform(client_id = nil)
    scope = client_id ? Client.where(id: client_id) : Client.where(active: true)

    scope.find_each do |client|
      process_client(client)
    rescue StandardError => e
      Rails.logger.error "[ProcessCashbackCampaigns] Erro: #{e.message}"
    end
  end

  private

  def process_client(client)
    running_campaigns = client.campaigns.running
    return if running_campaigns.empty?

    unless client.shopify_shop_url.present? && client.shopify_access_token.present?
      return
    end

    shopify_service = Shopify::DiscountService.new(client)

    orders = Order.joins(:customer)
                  .where(customers: { client_id: client.id })
                  .order(created_at: :desc)

    orders.find_each do |order|
      running_campaigns.each do |campaign|
        process_order_for_campaign(campaign, order, shopify_service)
      rescue StandardError => e
        Rails.logger.error "[ProcessCashbackCampaigns] Erro: #{e.message}"
      end
    end
  end

  def process_order_for_campaign(campaign, order, shopify_service)
    customer = order.customer
    return unless customer.present?

    already_sent = CampaignAction.exists?(
      campaign_id: campaign.id,
      order_id:    order.id,
      customer_id: customer.id,
      kind:        CampaignAction.kinds[:sent]
    )

    return if already_sent

    case campaign.kind
    when 'cashback'
      process_cashback(campaign, order, customer, shopify_service)
    when 'cashback_expiration'
      process_cashback_expiration(campaign, order, customer, shopify_service)
    end
  end

  def process_cashback(campaign, order, customer, shopify_service)
    purchase_date  = (order.shopify_creation_date || order.created_at).to_date
    scheduled_date = purchase_date + campaign.days_after_purchase.days

    return if Date.current < scheduled_date
    return if Date.current > scheduled_date + 3.days

    discount = shopify_service.find_by_order(order)

    unless discount.present?
      return
    end

    if discount[:is_expired]
      CampaignAction.create!(
        campaign:      campaign,
        customer:      customer,
        order:         order,
        kind:          :cancelled,
        scheduled_for: scheduled_date.to_datetime
      )
      return
    end

    return if CampaignAction.exists?(
      campaign_id: campaign.id,
      order_id:    order.id,
      customer_id: customer.id,
      kind:        CampaignAction.kinds[:pending]
    )

    action = CampaignAction.create!(
      campaign:      campaign,
      customer:      customer,
      order:         order,
      kind:          :pending,
      scheduled_for: scheduled_date.to_datetime
    )

    SendCampaignNotificationJob.perform_later(action.id, discount[:code])
  end

  def process_cashback_expiration(campaign, order, customer, shopify_service)
    discount = shopify_service.find_by_order(order)

    unless discount.present?
      return
    end

    unless discount[:ends_at].present?
      return
    end

    expiration_date = discount[:ends_at].to_date
    send_date       = expiration_date - campaign.days_after_purchase.days

    return if Date.current < send_date

    if discount[:is_expired] || Date.current > expiration_date
      CampaignAction.create!(
        campaign:      campaign,
        customer:      customer,
        order:         order,
        kind:          :cancelled,
        scheduled_for: send_date.to_datetime
      )
      return
    end

    return if CampaignAction.exists?(
      campaign_id: campaign.id,
      order_id:    order.id,
      customer_id: customer.id,
      kind:        CampaignAction.kinds[:pending]
    )

    action = CampaignAction.create!(
      campaign:      campaign,
      customer:      customer,
      order:         order,
      kind:          :pending,
      scheduled_for: send_date.to_datetime
    )

    SendCampaignNotificationJob.perform_later(action.id, discount[:code])
  end
end
