class CreateShopifyEvents < ActiveRecord::Migration[7.2]
  def change
    create_table :shopify_events do |t|
      t.references :client, null: false, foreign_key: true
      t.references :integration_user, null: false, foreign_key: true

      t.string :kind
      t.string :session_id
      t.string :shopify_event_id

      t.jsonb :payload, default: {}

      t.timestamps
    end

    add_index :shopify_events, :session_id
    add_index :shopify_events, :kind
    add_index :shopify_events, :shopify_event_id
  end
end