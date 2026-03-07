class CreateIntegrationUsers < ActiveRecord::Migration[7.2]
  def change
    create_table :integration_users do |t|
      t.string  :name,       null: false
      t.string  :slug,       null: false
      t.string  :api_secret, null: false
      t.boolean :active,     null: false, default: true

      t.timestamps
    end

    add_index :integration_users, :slug, unique: true
  end
end
