class CreateCustomers < ActiveRecord::Migration[7.0]
  def change
    create_table :customers do |t|
      t.string  :shopify_customer_id

      t.string  :name
      t.string  :email
      t.string  :phone

      t.string  :first_name
      t.string  :last_name
      t.string  :currency
      t.text    :tags

      t.integer :orders_count
      t.decimal :total_spent, precision: 12, scale: 2

      t.boolean :verified_email
      t.boolean :tax_exempt

      t.datetime :shopify_created_at
      t.datetime :shopify_updated_at

      t.string :default_address_name
      t.string :default_address_company
      t.string :default_address_phone
      t.string :default_address_address1
      t.string :default_address_address2
      t.string :default_address_city
      t.string :default_address_province
      t.string :default_address_country
      t.string :default_address_zip
      t.string :default_address_country_code
      t.string :default_address_province_code

      t.timestamps
    end

    add_index :customers, :shopify_customer_id, unique: true
    add_index :customers, :email
  end
end