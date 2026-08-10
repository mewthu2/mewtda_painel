class AddSalesDashboardEnabledToClients < ActiveRecord::Migration[7.2]
  def change
    add_column :clients, :sales_dashboard_enabled, :boolean, default: false, null: false
  end
end
