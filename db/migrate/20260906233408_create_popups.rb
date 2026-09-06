class CreatePopups < ActiveRecord::Migration[7.2]
  def change
    create_table :popups do |t|
      t.references :client, null: false, foreign_key: true, index: { unique: true }
      t.boolean :active, null: false, default: false
      t.string :title
      t.text :description
      t.string :coupon_code
      t.string :button_text, null: false, default: 'Cadastrar'
      t.string :accent_color, null: false, default: '#7c3aed'
      t.string :template, null: false, default: 'template_1'
      t.string :size, null: false, default: 'medium'
      t.integer :reappear_after_hours, null: false, default: 24
      t.string :public_token, null: false

      t.timestamps
    end

    add_index :popups, :public_token, unique: true
  end
end
