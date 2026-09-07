class CreatePopupSubmissions < ActiveRecord::Migration[7.2]
  def change
    create_table :popup_submissions do |t|
      t.references :popup, null: false, foreign_key: true
      t.string :name, null: false
      t.string :email, null: false
      t.string :phone
      t.string :shopify_customer_id
      t.string :status, null: false, default: 'success'

      t.datetime :created_at, null: false
    end

    add_index :popup_submissions, %i[popup_id status]
  end
end
