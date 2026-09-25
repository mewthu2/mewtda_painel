class CreateEmailTemplates < ActiveRecord::Migration[7.2]
  def change
    create_table :email_templates do |t|
      t.references :client, null: false, foreign_key: true
      t.string :name, null: false
      t.string :subject, null: false
      t.string :heading, null: false
      t.text :body, null: false
      t.string :button_text, null: false
      t.string :button_url
      t.string :coupon_code
      t.string :accent_color, null: false, default: '#7c3aed'
      t.string :layout, null: false, default: 'image_top'
      t.integer :trigger_kind, null: false, default: 0
      t.jsonb :trigger_config, null: false, default: {}
      t.boolean :active, null: false, default: false

      t.timestamps
    end
  end
end
