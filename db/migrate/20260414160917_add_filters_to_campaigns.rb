class AddFiltersToCampaigns < ActiveRecord::Migration[7.2]
  def change
    add_column :campaigns, :filters, :jsonb, default: {}, null: false
    add_index  :campaigns, :filters, using: :gin
  end
end
