class AddTrackingToOrders < ActiveRecord::Migration[7.2]
  def change
    add_column :orders, :tracking_number, :string
    add_column :orders, :tracking_company, :string
    add_column :orders, :tracking_url, :string
    add_column :orders, :fulfilled_at, :datetime
  end
end
