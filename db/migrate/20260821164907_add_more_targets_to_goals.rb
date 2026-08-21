class AddMoreTargetsToGoals < ActiveRecord::Migration[7.2]
  def change
    add_column :goals, :avg_ticket_target, :decimal, precision: 12, scale: 2
    add_column :goals, :conversion_rate_target, :decimal, precision: 6, scale: 2
    add_column :goals, :cac_target, :decimal, precision: 12, scale: 2
    add_column :goals, :tagged_revenue_target, :decimal, precision: 12, scale: 2
    add_column :goals, :tagged_revenue_tag, :string
  end
end
