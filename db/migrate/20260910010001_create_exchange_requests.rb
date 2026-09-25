class CreateExchangeRequests < ActiveRecord::Migration[7.2]
  def change
    create_table :exchange_requests do |t|
      t.references :client, null: false, foreign_key: true
      t.string :shopify_order_id, null: false
      t.string :shopify_order_number, null: false
      t.string :customer_email, null: false
      t.string :customer_name
      t.integer :status, null: false, default: 0
      t.string :coupon_code
      t.text :internal_notes

      t.timestamps
    end

    add_index :exchange_requests, %i[client_id status]
  end
end
