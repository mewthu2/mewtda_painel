class AddClientIdToProducts < ActiveRecord::Migration[7.2]
  def change
    add_reference :products, :client, null: true, foreign_key: true
    add_index :products, [:client_id, :shopify_variant_id], unique: true, name: 'index_products_on_client_and_variant'
    remove_index :products, :shopify_variant_id if index_exists?(:products, :shopify_variant_id)
  end
end
