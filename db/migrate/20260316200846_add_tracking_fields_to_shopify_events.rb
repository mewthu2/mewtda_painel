class AddTrackingFieldsToShopifyEvents < ActiveRecord::Migration[7.2]
  def change
    add_column :shopify_events, :event_id, :string unless column_exists?(:shopify_events, :event_id)
    add_column :shopify_events, :event_name, :string unless column_exists?(:shopify_events, :event_name)
    add_column :shopify_events, :event_type, :string unless column_exists?(:shopify_events, :event_type)
    add_column :shopify_events, :shop_domain, :string unless column_exists?(:shopify_events, :shop_domain)
    add_column :shopify_events, :event_timestamp, :datetime unless column_exists?(:shopify_events, :event_timestamp)
    add_column :shopify_events, :data, :jsonb unless column_exists?(:shopify_events, :data)
    add_column :shopify_events, :context, :jsonb unless column_exists?(:shopify_events, :context)
    add_column :shopify_events, :raw_payload, :jsonb unless column_exists?(:shopify_events, :raw_payload)

    add_index :shopify_events, :event_name unless index_exists?(:shopify_events, :event_name)
    add_index :shopify_events, :shop_domain unless index_exists?(:shopify_events, :shop_domain)
    add_index :shopify_events, [:session_id, :event_name] unless index_exists?(:shopify_events, [:session_id, :event_name])
  end
end