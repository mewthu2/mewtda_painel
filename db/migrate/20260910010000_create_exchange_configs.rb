class CreateExchangeConfigs < ActiveRecord::Migration[7.2]
  def change
    create_table :exchange_configs do |t|
      t.references :client, null: false, foreign_key: true, index: { unique: true }
      t.boolean :active, null: false, default: false
      t.string :company_name
      t.string :accent_color, null: false, default: '#7c3aed'
      t.text :instructions
      t.integer :return_window_days, null: false, default: 7
      t.integer :coupon_validity_days, null: false, default: 30
      t.string :public_token, null: false
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

    add_index :exchange_configs, :public_token, unique: true
  end
end
