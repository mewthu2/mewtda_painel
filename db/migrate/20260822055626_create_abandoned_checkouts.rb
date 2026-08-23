class CreateAbandonedCheckouts < ActiveRecord::Migration[7.2]
  def change
    create_table :abandoned_checkouts do |t|
      t.references :client, null: false, foreign_key: true
      t.references :customer, foreign_key: true
      t.string :shopify_checkout_id, null: false
      t.string :shopify_checkout_token
      t.string :email
      t.string :phone
      t.decimal :total_price, precision: 12, scale: 2
      t.string :currency
      t.datetime :checkout_created_at
      t.datetime :checkout_updated_at
      t.string :recovery_url
      t.datetime :completed_at
      t.jsonb :line_items, default: []
      t.datetime :first_notified_at
      t.text :first_message_sent
      t.string :first_coupon_code
      t.datetime :second_notified_at
      t.text :second_message_sent
      t.string :second_coupon_code

      t.timestamps
    end

    index_name = 'index_abandoned_checkouts_on_client_and_shopify_id'
    add_index :abandoned_checkouts, %i[client_id shopify_checkout_id], unique: true, name: index_name
  end
end
