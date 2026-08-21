class AddTotalShippingPriceToOrders < ActiveRecord::Migration[7.2]
  def change
    add_column :orders, :total_shipping_price, :decimal, precision: 12, scale: 2, default: 0.0, null: false
  end
end
