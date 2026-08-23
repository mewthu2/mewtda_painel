class ChangeCartRecoveryCouponToStaticCode < ActiveRecord::Migration[7.2]
  def change
    remove_column :campaigns, :coupon_percentage, :decimal, precision: 5, scale: 2
    remove_column :campaigns, :resend_coupon_percentage, :decimal, precision: 5, scale: 2
    add_column :campaigns, :coupon_code, :string
    add_column :campaigns, :resend_coupon_code, :string
  end
end
