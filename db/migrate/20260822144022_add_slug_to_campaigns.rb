class AddSlugToCampaigns < ActiveRecord::Migration[7.2]
  def change
    add_column :campaigns, :slug, :string
    add_index :campaigns, :slug, unique: true
  end
end
