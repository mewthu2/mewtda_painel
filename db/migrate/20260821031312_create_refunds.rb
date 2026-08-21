class CreateRefunds < ActiveRecord::Migration[7.2]
  def change
    create_table :refunds do |t|
      t.references :client, null: false, foreign_key: true
      t.references :order, null: true, foreign_key: true
      t.string :shopify_refund_id, null: false
      t.string :shopify_order_id, null: false
      t.datetime :processed_at, null: false
      t.decimal :amount, precision: 12, scale: 2, default: 0.0, null: false

      t.timestamps
    end

    add_index :refunds, %i[client_id shopify_refund_id], unique: true
    add_index :refunds, %i[client_id processed_at]
  end
end
