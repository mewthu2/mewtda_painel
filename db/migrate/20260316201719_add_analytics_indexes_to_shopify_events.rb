class AddAnalyticsIndexesToShopifyEvents < ActiveRecord::Migration[7.2]
  def change
    add_index :shopify_events, [:client_id, :kind] unless index_exists?(:shopify_events, [:client_id, :kind])

    add_index :shopify_events, [:shop_domain, :kind] unless index_exists?(:shopify_events, [:shop_domain, :kind])

    add_index :shopify_events, :event_timestamp unless index_exists?(:shopify_events, :event_timestamp)
  end
end