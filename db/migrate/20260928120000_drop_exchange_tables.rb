# O sistema de trocas/devoluções saiu do painel e virou um sistema separado.
class DropExchangeTables < ActiveRecord::Migration[7.2]
  def change
    drop_table :exchange_request_items do |t|
      t.references :exchange_request, null: false, foreign_key: true
      t.string :sku
      t.string :product_name, null: false
      t.string :variant_title
      t.integer :quantity, null: false, default: 1
      t.decimal :price, precision: 10, scale: 2, null: false
      t.integer :kind, null: false
      t.text :reason

      t.timestamps
    end

    drop_table :exchange_requests do |t|
      t.references :client, null: false, foreign_key: true
      t.string :shopify_order_id, null: false
      t.string :shopify_order_number, null: false
      t.string :customer_email, null: false
      t.string :customer_name
      t.integer :status, null: false, default: 0
      t.string :coupon_code
      t.text :internal_notes

      t.timestamps
      t.index %i[client_id status]
    end

    drop_table :exchange_configs do |t|
      t.references :client, null: false, foreign_key: true, index: { unique: true }
      t.boolean :active, null: false, default: false
      t.string :company_name
      t.string :accent_color, null: false, default: '#7c3aed'
      t.text :instructions
      t.integer :return_window_days, null: false, default: 7
      t.integer :coupon_validity_days, null: false, default: 30
      t.string :slug, null: false, index: { unique: true }
      t.string :requested_email_subject
      t.text :requested_email_body
      t.string :approved_email_subject
      t.text :approved_email_body
      t.string :rejected_email_subject
      t.text :rejected_email_body
      t.string :completed_email_subject
      t.text :completed_email_body

      t.timestamps
    end
  end
end
