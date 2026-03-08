class CreateOrderItems < ActiveRecord::Migration[7.2]
  def change
    create_table :order_items do |t|
      t.references :order, null: false, foreign_key: true
      t.references :product, foreign_key: true

      t.decimal :price, precision: 10, scale: 2
      t.integer :quantity
      t.string :sku
      t.boolean :canceled, default: false

      t.timestamps
    end
  end
end