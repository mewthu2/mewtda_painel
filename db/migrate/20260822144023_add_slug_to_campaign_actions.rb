class AddSlugToCampaignActions < ActiveRecord::Migration[7.2]
  def change
    add_column :campaign_actions, :slug, :string
    add_index :campaign_actions, :slug, unique: true
  end
end
