class CreateExchangeRequestItems < ActiveRecord::Migration[7.2]
  def change
    create_table :exchange_request_items do |t|
      t.references :exchange_request, null: false, foreign_key: true
      t.string :sku
      t.string :product_name, null: false
      t.string :variant_title
      t.integer :quantity, null: false, default: 1
      t.decimal :price, precision: 10, scale: 2, null: false
      t.integer :kind, null: false
      t.text :reason

      t.timestamps
    end
  end
end
