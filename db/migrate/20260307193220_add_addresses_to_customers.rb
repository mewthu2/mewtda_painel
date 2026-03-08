class AddAddressesToCustomers < ActiveRecord::Migration[7.2]
  def change
    add_column :customers, :addresses, :jsonb, default: [], null: false
  end
end