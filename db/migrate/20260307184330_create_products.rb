class CreateProducts < ActiveRecord::Migration[7.0]
  def change
    create_table :products do |t|
      t.string :sku

      t.string :shopify_product_id
      t.string :shopify_variant_id
      t.string :shopify_inventory_item_id
      t.string :shopify_product_name

      t.decimal :cost, precision: 10, scale: 2
      t.decimal :price, precision: 10, scale: 2
      t.decimal :compare_at_price, precision: 10, scale: 2

      t.string :vendor

      t.string :option1
      t.string :option2
      t.string :option3

      t.text :tags
      t.string :image_url

      t.timestamps
    end

    add_index :products, :sku
    add_index :products, :shopify_product_id
    add_index :products, :shopify_variant_id
    add_index :products, :shopify_inventory_item_id
  end
end