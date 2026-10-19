class CreateCustomAutomationRuns < ActiveRecord::Migration[7.2]
  def change
    create_table :custom_automation_runs do |t|
      t.references :client, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.string :kind, null: false
      t.string :status, null: false, default: 'pending'
      t.date :period_start, null: false
      t.date :period_end, null: false
      t.string :order_filter, null: false
      t.decimal :price_percentage, precision: 5, scale: 2, null: false
      t.integer :orders_count, null: false, default: 0
      t.decimal :total_value, precision: 14, scale: 2, null: false, default: 0
      t.jsonb :items, null: false, default: []
      t.jsonb :warnings, null: false, default: []
      t.string :tiny_note_id
      t.string :tiny_note_number
      t.text :tiny_response
      t.text :error_message
      t.datetime :emitted_at
      t.timestamps
    end

    add_index :custom_automation_runs, [:client_id, :kind, :created_at]
  end
end
