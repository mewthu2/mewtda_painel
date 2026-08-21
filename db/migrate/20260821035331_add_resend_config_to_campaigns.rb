class AddResendConfigToCampaigns < ActiveRecord::Migration[7.2]
  def change
    add_column :campaigns, :max_sends, :integer
    add_column :campaigns, :interval_days, :integer
  end
end
