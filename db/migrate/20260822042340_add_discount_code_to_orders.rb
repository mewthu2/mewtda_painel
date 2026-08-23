class AddDiscountCodeToOrders < ActiveRecord::Migration[7.2]
  def change
    add_column :orders, :discount_code, :string
    add_index :orders, :discount_code
  end
end
