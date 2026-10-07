class AddLandingPageToOrders < ActiveRecord::Migration[7.2]
  def change
    add_reference :orders, :landing_page, foreign_key: { on_delete: :nullify }, index: true
  end
end
