class CreateCampaignActions < ActiveRecord::Migration[7.2]
  def change
    create_table :campaign_actions do |t|
      t.references :campaign, null: false, foreign_key: true
      t.references :customer, null: false, foreign_key: true
      t.references :order, null: true, foreign_key: true
      t.integer :kind, default: 0, null: false
      t.integer :status, default: 0, null: false
      t.text :message_sent
      t.datetime :notified_at
      t.text :response
      t.text :error_message

      t.timestamps
    end

    add_index :campaign_actions, [:campaign_id, :status]
    add_index :campaign_actions, [:campaign_id, :kind]
    add_index :campaign_actions, :notified_at
  end
end