class CreateOrders < ActiveRecord::Migration[7.0]
  def change
    create_table :orders do |t|
      t.references :location, foreign_key: true
      t.references :customer, foreign_key: true

      t.string :shopify_order_id
      t.string :shopify_order_number

      t.string :kinds
      t.text :tags

      t.integer :staff_id
      t.string :staff_name

      t.datetime :shopify_creation_date

      t.jsonb :payments, default: []

      t.timestamps
    end

    add_index :orders, :shopify_order_id, unique: true
    add_index :orders, :shopify_order_number
  end
end