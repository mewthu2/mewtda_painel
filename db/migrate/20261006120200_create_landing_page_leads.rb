class CreateLandingPageLeads < ActiveRecord::Migration[7.2]
  def change
    create_table :landing_page_leads do |t|
      t.references :landing_page, null: false, foreign_key: true
      t.string :name, null: false
      t.string :email, null: false
      t.string :phone
      t.string :utm_source
      t.string :utm_medium
      t.string :utm_campaign
      t.string :utm_content
      t.string :utm_term
      t.boolean :existing_customer, null: false, default: false
      t.string :shopify_customer_id
      t.string :status, null: false
      t.timestamps
    end

    add_index :landing_page_leads, %i[landing_page_id email], unique: true
  end
end
