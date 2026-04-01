class AddDiscountCodeToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :discount_code, :string
    add_index :users, :discount_code
  end
end