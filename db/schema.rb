# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2026_03_07_193446) do
  create_schema "_heroku"

  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_stat_statements"
  enable_extension "plpgsql"

  create_table "attempts", force: :cascade do |t|
    t.bigint "kinds"
    t.bigint "status"
    t.text "requisition"
    t.text "params"
    t.string "error"
    t.string "status_code"
    t.string "message"
    t.string "exception"
    t.string "classification"
    t.string "cause"
    t.string "url"
    t.string "user"
    t.integer "bling_order_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "customers", force: :cascade do |t|
    t.string "shopify_customer_id"
    t.string "name"
    t.string "email"
    t.string "phone"
    t.string "first_name"
    t.string "last_name"
    t.string "currency"
    t.text "tags"
    t.integer "orders_count"
    t.decimal "total_spent", precision: 12, scale: 2
    t.boolean "verified_email"
    t.boolean "tax_exempt"
    t.datetime "shopify_created_at"
    t.datetime "shopify_updated_at"
    t.string "default_address_name"
    t.string "default_address_company"
    t.string "default_address_phone"
    t.string "default_address_address1"
    t.string "default_address_address2"
    t.string "default_address_city"
    t.string "default_address_province"
    t.string "default_address_country"
    t.string "default_address_zip"
    t.string "default_address_country_code"
    t.string "default_address_province_code"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "addresses", default: [], null: false
    t.index ["email"], name: "index_customers_on_email"
    t.index ["shopify_customer_id"], name: "index_customers_on_shopify_customer_id", unique: true
  end

  create_table "integration_users", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.string "api_secret", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_integration_users_on_slug", unique: true
  end

  create_table "locations", force: :cascade do |t|
    t.string "slug"
    t.string "name"
    t.decimal "kpi_ratio", precision: 10, scale: 4
    t.datetime "kpi_updated_at"
    t.string "shopify_location_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shopify_location_id"], name: "index_locations_on_shopify_location_id", unique: true
    t.index ["slug"], name: "index_locations_on_slug", unique: true
  end

  create_table "order_items", force: :cascade do |t|
    t.bigint "order_id", null: false
    t.bigint "product_id"
    t.decimal "price", precision: 10, scale: 2
    t.integer "quantity"
    t.string "sku"
    t.boolean "canceled", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_order_items_on_order_id"
    t.index ["product_id"], name: "index_order_items_on_product_id"
  end

  create_table "orders", force: :cascade do |t|
    t.bigint "location_id"
    t.bigint "customer_id"
    t.string "shopify_order_id"
    t.string "shopify_order_number"
    t.string "kinds"
    t.text "tags"
    t.integer "staff_id"
    t.string "staff_name"
    t.datetime "shopify_creation_date"
    t.jsonb "payments", default: []
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_orders_on_customer_id"
    t.index ["location_id"], name: "index_orders_on_location_id"
    t.index ["shopify_order_id"], name: "index_orders_on_shopify_order_id", unique: true
    t.index ["shopify_order_number"], name: "index_orders_on_shopify_order_number"
  end

  create_table "products", force: :cascade do |t|
    t.string "sku"
    t.string "shopify_product_id"
    t.string "shopify_variant_id"
    t.string "shopify_inventory_item_id"
    t.string "shopify_product_name"
    t.decimal "cost", precision: 10, scale: 2
    t.decimal "price", precision: 10, scale: 2
    t.decimal "compare_at_price", precision: 10, scale: 2
    t.string "vendor"
    t.string "option1"
    t.string "option2"
    t.string "option3"
    t.text "tags"
    t.string "image_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shopify_inventory_item_id"], name: "index_products_on_shopify_inventory_item_id"
    t.index ["shopify_product_id"], name: "index_products_on_shopify_product_id"
    t.index ["shopify_variant_id"], name: "index_products_on_shopify_variant_id"
    t.index ["sku"], name: "index_products_on_sku"
  end

  create_table "profiles", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "users", force: :cascade do |t|
    t.string "name"
    t.string "phone"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.string "confirmation_token"
    t.string "unlock_token"
    t.datetime "confirmed_at"
    t.datetime "confirmation_sent_at"
    t.string "unconfirmed_email"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "profile_id"
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["profile_id"], name: "index_users_on_profile_id"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
  end

  add_foreign_key "order_items", "orders"
  add_foreign_key "order_items", "products"
  add_foreign_key "orders", "customers"
  add_foreign_key "orders", "locations"
  add_foreign_key "users", "profiles"
end
