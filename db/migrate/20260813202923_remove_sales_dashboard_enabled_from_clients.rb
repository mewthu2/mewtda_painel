class RemoveSalesDashboardEnabledFromClients < ActiveRecord::Migration[7.2]
  def change
    remove_column :clients, :sales_dashboard_enabled, :boolean
  end
end
