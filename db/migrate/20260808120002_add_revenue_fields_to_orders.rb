class AddRevenueFieldsToOrders < ActiveRecord::Migration[7.2]
  def change
    add_column :orders, :subtotal_price, :decimal, precision: 12, scale: 2
    add_column :orders, :total_discounts, :decimal, precision: 12, scale: 2
    add_column :orders, :total_price, :decimal, precision: 12, scale: 2
    add_column :orders, :cancelled_at, :datetime

    add_index :orders, :cancelled_at
  end
end
