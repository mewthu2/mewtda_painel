class AddSyncTimestampsToClients < ActiveRecord::Migration[7.2]
  def change
    add_column :clients, :orders_synced_at, :datetime
    add_column :clients, :refunds_synced_at, :datetime
  end
end
