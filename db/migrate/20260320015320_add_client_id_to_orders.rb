class AddClientIdToOrders < ActiveRecord::Migration[7.2]
  def change
    add_reference :orders, :client, null: true, foreign_key: true

    add_index :orders, [:client_id, :shopify_order_id], unique: true

    unless column_exists?(:locations, :client_id)
      add_reference :locations, :client, null: true, foreign_key: true
    end
  end
end
