class AddCartRecoveryConfigToCampaigns < ActiveRecord::Migration[7.2]
  def change
    add_column :campaigns, :send_delay_minutes, :integer
    add_column :campaigns, :include_coupon, :boolean, default: false, null: false
    add_column :campaigns, :coupon_percentage, :decimal, precision: 5, scale: 2
    add_column :campaigns, :resend_enabled, :boolean, default: false, null: false
    add_column :campaigns, :resend_delay_hours, :integer
    add_column :campaigns, :resend_message, :text
    add_column :campaigns, :resend_include_coupon, :boolean, default: false, null: false
    add_column :campaigns, :resend_coupon_percentage, :decimal, precision: 5, scale: 2
  end
end
