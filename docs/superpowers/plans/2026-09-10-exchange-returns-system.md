# Sistema de Trocas e Devoluções Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a public, per-client branded page where Shopify customers request an exchange or return by order number + e-mail, plus the CRM screens to configure it and to review/approve requests — including automatic e-mail notifications and a fixed-value Shopify coupon on approval.

**Architecture:** Three new models (`ExchangeConfig`, `ExchangeRequest`, `ExchangeRequestItem`) scoped to `Client`, exactly following the existing `Popup`/`PopupSubmission` pattern (`public_token`, `has_one_attached` logo, `ClientScoped` admin controllers). Order lookup hits the Shopify Admin REST API live (no dependency on the daily sync job). All Shopify writes reuse/extend existing services (`Shopify::CreateDiscountCode`). E-mail sending is new infrastructure (`Ses::SendEmailService`), since none exists yet in the app.

**Tech Stack:** Rails 7.2, Minitest (no fixtures — records built inline with `create!`, external calls stubbed via `SomeClass.stub :new, fake` or `Minitest::Mock`), Sidekiq (ActiveJob), `shopify_api` gem, `aws-sdk-sesv2`, Sprockets/SCSS (no JS framework — server-rendered ERB).

**Spec:** `docs/superpowers/specs/2026-09-10-exchange-returns-system-design.md`

## Global Constraints

- v1 never writes a return/exchange to Shopify itself — only reads orders and creates discount codes. The lojista's team processes the actual refund/new order manually in Shopify admin.
- Approval/rejection/completion is decided at the whole-`ExchangeRequest` level, not per item. `kind` (`troca`/`devolucao`) is chosen per item only by the end customer.
- Coupons are a **fixed BRL amount** (sum of `price × quantity` of the approved request's `troca` items), never a percentage, and only generated when the request has at least one `troca` item.
- Coupon validity is a **duration** (`coupon_validity_days` from the moment it's generated), not a fixed calendar range.
- Eligibility is computed from `fulfilled_at` (delivery/dispatch date), not the order date: no `fulfilled_at` → nothing selectable yet; within `return_window_days` → troca or devolução; past it → troca only; `cancelled_at` present → blocked entirely.
- The order lookup is always a **live** Shopify Admin API call (never the locally-synced `orders` table), because the daily sync job can lag behind a same-day purchase.
- If a client's SES sending domain isn't verified (`client.ses_domain_verified?` is false), notification jobs log a warning and skip sending — they never raise or block the exchange/approval flow.
- Follow existing conventions exactly: `ClientScoped` concern for admin controllers, `skip_before_action :authenticate_user!, :redirect_affiliate_to_events!` + `protect_from_forgery with: :null_session` for public controllers (see `Widget::PopupController`), Minitest with inline `create!` fixtures and `.stub`/`Minitest::Mock` for external services, Sprockets `*= require pages/<name>` for page-scoped SCSS.

---

## File Structure

```
db/migrate/
  <ts1>_create_exchange_configs.rb
  <ts2>_create_exchange_requests.rb
  <ts3>_create_exchange_request_items.rb

app/models/
  exchange_config.rb
  exchange_request.rb
  exchange_request_item.rb
  client.rb                       (modify: associations)
  shopify/create_discount_code.rb (modify: fixed-amount support)

app/services/
  shopify/find_order_for_exchange.rb
  exchange/eligibility_calculator.rb
  exchange/lookup_throttle.rb
  exchange/approve.rb
  ses/send_email_service.rb

app/jobs/
  send_exchange_email_job.rb

app/controllers/
  widget/exchanges_controller.rb
  exchange_configs_controller.rb
  exchange_requests_controller.rb

app/views/
  widget/exchanges/new.html.erb
  widget/exchanges/lookup.html.erb
  widget/exchanges/confirmation.html.erb
  exchange_configs/edit.html.erb
  exchange_requests/index.html.erb
  exchange_requests/show.html.erb

app/assets/stylesheets/
  admin.scss                      (modify: add require)
  pages/exchanges.scss

config/routes.rb                  (modify)
app/views/layouts/partials/_sidebar.html.erb (modify)

test/models/
  exchange_config_test.rb
  exchange_request_test.rb
  exchange_request_item_test.rb
test/services/
  shopify/find_order_for_exchange_test.rb
  shopify/create_discount_code_test.rb
  exchange/eligibility_calculator_test.rb
  exchange/lookup_throttle_test.rb
  exchange/approve_test.rb
  ses/send_email_service_test.rb
test/jobs/
  send_exchange_email_job_test.rb
test/controllers/
  widget/exchanges_controller_test.rb
  exchange_configs_controller_test.rb
  exchange_requests_controller_test.rb
```

---

### Task 1: Database schema

**Files:**
- Create: `db/migrate/20260910010000_create_exchange_configs.rb`
- Create: `db/migrate/20260910010001_create_exchange_requests.rb`
- Create: `db/migrate/20260910010002_create_exchange_request_items.rb`
- Modify: `db/schema.rb` (generated by running the migrations)

**Interfaces:**
- Produces: tables `exchange_configs`, `exchange_requests`, `exchange_request_items` with the columns below, consumed by every later task.

- [ ] **Step 1: Write the three migrations**

`db/migrate/20260910010000_create_exchange_configs.rb`:
```ruby
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
```

`db/migrate/20260910010001_create_exchange_requests.rb`:
```ruby
class CreateExchangeRequests < ActiveRecord::Migration[7.2]
  def change
    create_table :exchange_requests do |t|
      t.references :client, null: false, foreign_key: true
      t.string :shopify_order_id, null: false
      t.string :shopify_order_number, null: false
      t.string :customer_email, null: false
      t.string :customer_name
      t.integer :status, null: false, default: 0
      t.string :coupon_code
      t.text :internal_notes

      t.timestamps
    end

    add_index :exchange_requests, %i[client_id status]
  end
end
```

`db/migrate/20260910010002_create_exchange_request_items.rb`:
```ruby
class CreateExchangeRequestItems < ActiveRecord::Migration[7.2]
  def change
    create_table :exchange_request_items do |t|
      t.references :exchange_request, null: false, foreign_key: true
      t.string :sku
      t.string :product_name, null: false
      t.string :variant_title
      t.integer :quantity, null: false, default: 1
      t.decimal :price, precision: 10, scale: 2, null: false
      t.integer :kind, null: false
      t.text :reason

      t.timestamps
    end
  end
end
```

- [ ] **Step 2: Run the migrations**

Run: `bin/rails db:migrate`
Expected: all three migrations run, `db/schema.rb` is updated with the new tables (check `git diff db/schema.rb` shows the three `create_table` blocks and a bumped version).

- [ ] **Step 3: Commit**

```bash
git add db/migrate/20260910010000_create_exchange_configs.rb \
        db/migrate/20260910010001_create_exchange_requests.rb \
        db/migrate/20260910010002_create_exchange_request_items.rb \
        db/schema.rb
git commit -m "feat: add exchange_configs, exchange_requests and exchange_request_items tables"
```

---

### Task 2: `ExchangeConfig` model

**Files:**
- Create: `app/models/exchange_config.rb`
- Modify: `app/models/client.rb` (add `has_one :exchange_config, dependent: :destroy`)
- Test: `test/models/exchange_config_test.rb`

**Interfaces:**
- Consumes: `exchange_configs` table (Task 1).
- Produces: `ExchangeConfig#public_token` (auto-generated string), `#active?`, `#return_window_days`, `#coupon_validity_days`, and the 8 e-mail subject/body accessors — all consumed by Tasks 5, 6, 9, 10, 11, 12, 13.

- [ ] **Step 1: Write the failing test**

```ruby
require 'test_helper'

class ExchangeConfigTest < ActiveSupport::TestCase
  def build_client
    Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
  end

  test 'generates a public_token on create' do
    config = ExchangeConfig.create!(client: build_client)
    assert config.public_token.present?
  end

  test 'does not overwrite an existing public_token on update' do
    config = ExchangeConfig.create!(client: build_client)
    token = config.public_token

    config.update!(company_name: 'Loja Teste')

    assert_equal token, config.reload.public_token
  end

  test 'defaults to inactive, 7 day return window and 30 day coupon validity' do
    config = ExchangeConfig.create!(client: build_client)
    assert_not config.active?
    assert_equal 7, config.return_window_days
    assert_equal 30, config.coupon_validity_days
  end

  test 'requires company_name when active' do
    config = ExchangeConfig.new(client: build_client, active: true)
    assert_not config.valid?
    assert_includes config.errors.attribute_names, :company_name
  end

  test 'allows a blank company_name when inactive' do
    config = ExchangeConfig.new(client: build_client, active: false)
    assert config.valid?, config.errors.full_messages.to_s
  end

  test 'rejects a non-hex accent_color' do
    config = ExchangeConfig.new(client: build_client, accent_color: 'purple')
    assert_not config.valid?
  end

  test 'rejects a zero or negative return_window_days' do
    config = ExchangeConfig.new(client: build_client, return_window_days: 0)
    assert_not config.valid?
  end

  test 'a client has one exchange_config, destroyed with it' do
    client = build_client
    config = ExchangeConfig.create!(client: client)

    client.destroy

    assert_not ExchangeConfig.exists?(config.id)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/models/exchange_config_test.rb`
Expected: FAIL — `uninitialized constant ExchangeConfig`

- [ ] **Step 3: Write the model and the `Client` association**

`app/models/exchange_config.rb`:
```ruby
class ExchangeConfig < ApplicationRecord
  belongs_to :client
  has_one_attached :logo

  before_create :generate_public_token

  validates :accent_color, format: { with: /\A#[0-9a-fA-F]{6}\z/ }, allow_blank: true
  validates :return_window_days, numericality: { only_integer: true, greater_than: 0 }
  validates :coupon_validity_days, numericality: { only_integer: true, greater_than: 0 }
  validates :company_name, presence: true, if: :active?

  private

  def generate_public_token
    self.public_token ||= SecureRandom.hex(16)
  end
end
```

In `app/models/client.rb`, add alongside the other `has_one`/`has_many` declarations (near `has_one :popup, dependent: :destroy`):
```ruby
  has_one :exchange_config, dependent: :destroy
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/models/exchange_config_test.rb`
Expected: PASS (8 tests)

- [ ] **Step 5: Commit**

```bash
git add app/models/exchange_config.rb app/models/client.rb test/models/exchange_config_test.rb
git commit -m "feat: add ExchangeConfig model"
```

---

### Task 3: `ExchangeRequestItem` model

**Files:**
- Create: `app/models/exchange_request_item.rb`
- Test: `test/models/exchange_request_item_test.rb`

**Interfaces:**
- Consumes: `exchange_request_items` table (Task 1).
- Produces: `ExchangeRequestItem#kind` enum (`troca: 0`, `devolucao: 1`) — consumed by Tasks 4, 11, 12.

- [ ] **Step 1: Write the failing test**

```ruby
require 'test_helper'

class ExchangeRequestItemTest < ActiveSupport::TestCase
  def build_exchange_request
    client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
    ExchangeRequest.create!(
      client: client, shopify_order_id: '1', shopify_order_number: '#1001',
      customer_email: 'ana@example.com'
    )
  end

  test 'valid with required fields' do
    item = ExchangeRequestItem.new(
      exchange_request: build_exchange_request, product_name: 'Camiseta P',
      quantity: 1, price: 99.9, kind: :troca
    )
    assert item.valid?, item.errors.full_messages.to_s
  end

  test 'requires product_name' do
    item = ExchangeRequestItem.new(exchange_request: build_exchange_request, quantity: 1, price: 10, kind: :troca)
    assert_not item.valid?
    assert_includes item.errors.attribute_names, :product_name
  end

  test 'rejects a zero quantity' do
    item = ExchangeRequestItem.new(
      exchange_request: build_exchange_request, product_name: 'X', quantity: 0, price: 10, kind: :troca
    )
    assert_not item.valid?
  end

  test 'rejects a negative price' do
    item = ExchangeRequestItem.new(
      exchange_request: build_exchange_request, product_name: 'X', quantity: 1, price: -1, kind: :troca
    )
    assert_not item.valid?
  end

  test 'kind defaults to the troca/devolucao enum' do
    item = ExchangeRequestItem.new(kind: :devolucao)
    assert item.devolucao?
    assert_not item.troca?
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/models/exchange_request_item_test.rb`
Expected: FAIL — `uninitialized constant ExchangeRequestItem` (and `ExchangeRequest`, addressed next task — this test file requires both; it will keep failing until Task 4 lands, which is fine since Task 4 is next and re-runs this file too)

- [ ] **Step 3: Write the model**

`app/models/exchange_request_item.rb`:
```ruby
class ExchangeRequestItem < ApplicationRecord
  belongs_to :exchange_request

  enum kind: { troca: 0, devolucao: 1 }

  validates :product_name, presence: true
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :price, numericality: { greater_than_or_equal_to: 0 }
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/models/exchange_request_item_test.rb`
Expected: still FAILs on `uninitialized constant ExchangeRequest` — expected at this point, resolved by Task 4. Do not commit yet if it still fails; if `ExchangeRequest` already exists from a prior partial run, expect PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add app/models/exchange_request_item.rb test/models/exchange_request_item_test.rb
git commit -m "feat: add ExchangeRequestItem model"
```

---

### Task 4: `ExchangeRequest` model

**Files:**
- Create: `app/models/exchange_request.rb`
- Modify: `app/models/client.rb` (add `has_many :exchange_requests, dependent: :destroy`)
- Test: `test/models/exchange_request_test.rb`

**Interfaces:**
- Consumes: `exchange_requests` table (Task 1), `ExchangeRequestItem#kind` enum (Task 3).
- Produces: `ExchangeRequest#status` enum (`pending: 0, approved: 1, rejected: 2, completed: 3`), `#troca_items`, `#troca_total` — consumed by Tasks 11, 12, 13, 14.

- [ ] **Step 1: Write the failing test**

```ruby
require 'test_helper'

class ExchangeRequestTest < ActiveSupport::TestCase
  def build_client
    Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
  end

  def build_request(overrides = {})
    ExchangeRequest.create!({
      client: build_client, shopify_order_id: '1', shopify_order_number: '#1001',
      customer_email: 'ana@example.com'
    }.merge(overrides))
  end

  test 'defaults to pending status' do
    assert build_request.pending?
  end

  test 'requires shopify_order_id, shopify_order_number and customer_email' do
    request = ExchangeRequest.new(client: build_client)
    assert_not request.valid?
    assert_includes request.errors.attribute_names, :shopify_order_id
    assert_includes request.errors.attribute_names, :shopify_order_number
    assert_includes request.errors.attribute_names, :customer_email
  end

  test 'troca_total sums only troca items' do
    request = build_request
    request.exchange_request_items.create!(product_name: 'A', quantity: 2, price: 50, kind: :troca)
    request.exchange_request_items.create!(product_name: 'B', quantity: 1, price: 30, kind: :devolucao)

    assert_equal 100.0, request.troca_total
  end

  test 'troca_total is zero without any troca item' do
    request = build_request
    request.exchange_request_items.create!(product_name: 'B', quantity: 1, price: 30, kind: :devolucao)

    assert_equal 0.0, request.troca_total
  end

  test 'destroying a request destroys its items' do
    request = build_request
    item = request.exchange_request_items.create!(product_name: 'A', quantity: 1, price: 10, kind: :troca)

    request.destroy

    assert_not ExchangeRequestItem.exists?(item.id)
  end

  test 'a client has many exchange_requests, destroyed with it' do
    client = build_client
    request = build_request(client: client)

    client.destroy

    assert_not ExchangeRequest.exists?(request.id)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/models/exchange_request_test.rb`
Expected: FAIL — `uninitialized constant ExchangeRequest`

- [ ] **Step 3: Write the model and the `Client` association**

`app/models/exchange_request.rb`:
```ruby
class ExchangeRequest < ApplicationRecord
  belongs_to :client
  has_many :exchange_request_items, dependent: :destroy

  enum status: { pending: 0, approved: 1, rejected: 2, completed: 3 }

  validates :shopify_order_id, :shopify_order_number, :customer_email, presence: true

  def troca_items
    exchange_request_items.select(&:troca?)
  end

  def troca_total
    troca_items.sum { |item| item.price.to_f * item.quantity.to_i }
  end
end
```

In `app/models/client.rb`, alongside `has_many :refunds, dependent: :destroy`:
```ruby
  has_many :exchange_requests, dependent: :destroy
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/models/exchange_request_test.rb test/models/exchange_request_item_test.rb`
Expected: PASS (both files, 11 tests total)

- [ ] **Step 5: Commit**

```bash
git add app/models/exchange_request.rb app/models/client.rb test/models/exchange_request_test.rb
git commit -m "feat: add ExchangeRequest model"
```

---

### Task 5: `Shopify::FindOrderForExchange` service

**Files:**
- Create: `app/services/shopify/find_order_for_exchange.rb`
- Test: `test/services/shopify/find_order_for_exchange_test.rb`

**Interfaces:**
- Consumes: `Client#shopify_configured?`, `Client#shopify_shop_url`, `Client#shopify_access_token` (existing).
- Produces: `Shopify::FindOrderForExchange.call(client:, order_number:, email:)` → `nil` or a Hash `{ id:, number:, email:, cancelled:, fulfilled_at:, items: [{ sku:, product_name:, variant_title:, quantity:, price: }] }` — consumed by Tasks 6, 12.

- [ ] **Step 1: Write the failing test**

```ruby
require 'test_helper'

class Shopify::FindOrderForExchangeTest < ActiveSupport::TestCase
  def build_client
    Client.create!(
      name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com",
      shopify_shop_url: 'loja-teste.myshopify.com', shopify_access_token: 'token123'
    )
  end

  class FakeRestClient
    def initialize(orders)
      @orders = orders
    end

    def get(path:, query:)
      raise "unexpected path #{path}" unless path == 'orders'
      raise "expected name query, got #{query}" unless query[:name]

      OpenStruct.new(body: { 'orders' => @orders })
    end
  end

  def shopify_order(overrides = {})
    {
      'id' => 555_001, 'name' => '#1001', 'email' => 'ana@example.com', 'cancelled_at' => nil,
      'fulfillments' => [{ 'created_at' => '2026-09-01T10:00:00-03:00' }],
      'line_items' => [
        { 'sku' => 'SKU-1', 'title' => 'Camiseta', 'variant_title' => 'P', 'quantity' => 2, 'price' => '99.90' }
      ]
    }.merge(overrides)
  end

  test 'returns the normalized order when the number and e-mail match' do
    fake = FakeRestClient.new([shopify_order])

    ShopifyAPI::Clients::Rest::Admin.stub :new, fake do
      result = Shopify::FindOrderForExchange.call(client: build_client, order_number: '1001', email: 'ANA@example.com')

      assert_equal '555001', result[:id]
      assert_equal '#1001', result[:number]
      assert_equal false, result[:cancelled]
      assert_equal Time.parse('2026-09-01T10:00:00-03:00'), result[:fulfilled_at]
      assert_equal 1, result[:items].size
      assert_equal 'SKU-1', result[:items].first[:sku]
      assert_equal 2, result[:items].first[:quantity]
      assert_equal 99.90, result[:items].first[:price]
    end
  end

  test 'accepts an order_number already prefixed with #' do
    fake = FakeRestClient.new([shopify_order])

    ShopifyAPI::Clients::Rest::Admin.stub :new, fake do
      result = Shopify::FindOrderForExchange.call(client: build_client, order_number: '#1001', email: 'ana@example.com')
      assert_equal '#1001', result[:number]
    end
  end

  test 'returns nil when the e-mail does not match' do
    fake = FakeRestClient.new([shopify_order])

    ShopifyAPI::Clients::Rest::Admin.stub :new, fake do
      assert_nil Shopify::FindOrderForExchange.call(client: build_client, order_number: '1001', email: 'outro@example.com')
    end
  end

  test 'returns nil when no order is found' do
    fake = FakeRestClient.new([])

    ShopifyAPI::Clients::Rest::Admin.stub :new, fake do
      assert_nil Shopify::FindOrderForExchange.call(client: build_client, order_number: '9999', email: 'ana@example.com')
    end
  end

  test 'marks cancelled orders' do
    fake = FakeRestClient.new([shopify_order('cancelled_at' => '2026-09-02T09:00:00-03:00')])

    ShopifyAPI::Clients::Rest::Admin.stub :new, fake do
      result = Shopify::FindOrderForExchange.call(client: build_client, order_number: '1001', email: 'ana@example.com')
      assert_equal true, result[:cancelled]
    end
  end

  test 'returns nil without raising when the client has no Shopify credentials' do
    client = Client.create!(name: 'Sem Shopify', email: "sem-shopify-#{SecureRandom.hex(4)}@example.com")
    assert_nil Shopify::FindOrderForExchange.call(client: client, order_number: '1001', email: 'ana@example.com')
  end

  test 'returns nil without raising when the API call errors' do
    fake_class = Class.new { def get(*) = raise(StandardError, 'boom') }

    ShopifyAPI::Clients::Rest::Admin.stub :new, fake_class.new do
      assert_nil Shopify::FindOrderForExchange.call(client: build_client, order_number: '1001', email: 'ana@example.com')
    end
  end

  test 'returns nil without raising when the order has no fulfillment yet' do
    fake = FakeRestClient.new([shopify_order('fulfillments' => [])])

    ShopifyAPI::Clients::Rest::Admin.stub :new, fake do
      result = Shopify::FindOrderForExchange.call(client: build_client, order_number: '1001', email: 'ana@example.com')
      assert_nil result[:fulfilled_at]
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/shopify/find_order_for_exchange_test.rb`
Expected: FAIL — `uninitialized constant Shopify::FindOrderForExchange`

- [ ] **Step 3: Write the service**

`app/services/shopify/find_order_for_exchange.rb`:
```ruby
class Shopify::FindOrderForExchange
  ORDER_FIELDS = 'id,name,email,cancelled_at,line_items,fulfillments'.freeze

  def self.call(client:, order_number:, email:)
    return nil unless client.shopify_configured?

    name = order_number.to_s.strip
    name = "##{name}" unless name.start_with?('#')

    session = ShopifyAPI::Auth::Session.new(shop: client.shopify_shop_url, access_token: client.shopify_access_token)
    api_client = ShopifyAPI::Clients::Rest::Admin.new(session: session)

    response = api_client.get(path: 'orders', query: { name: name, status: 'any', fields: ORDER_FIELDS })
    shopify_order = Array(response.body['orders']).first
    return nil unless shopify_order
    return nil unless shopify_order['email'].to_s.casecmp(email.to_s.strip).zero?

    normalize(shopify_order)
  rescue StandardError => e
    Rails.logger.error("[Shopify::FindOrderForExchange] #{e.class} #{e.message}")
    nil
  end

  def self.normalize(shopify_order)
    fulfillment = Array(shopify_order['fulfillments']).max_by { |f| f['created_at'].to_s }

    {
      id: shopify_order['id'].to_s,
      number: shopify_order['name'],
      email: shopify_order['email'],
      cancelled: shopify_order['cancelled_at'].present?,
      fulfilled_at: fulfillment&.dig('created_at').presence && Time.parse(fulfillment['created_at']),
      items: Array(shopify_order['line_items']).map do |line_item|
        {
          sku: line_item['sku'],
          product_name: line_item['title'],
          variant_title: line_item['variant_title'],
          quantity: line_item['quantity'].to_i,
          price: line_item['price'].to_f
        }
      end
    }
  end
  private_class_method :normalize
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/shopify/find_order_for_exchange_test.rb`
Expected: PASS (8 tests)

- [ ] **Step 5: Commit**

```bash
git add app/services/shopify/find_order_for_exchange.rb test/services/shopify/find_order_for_exchange_test.rb
git commit -m "feat: add Shopify::FindOrderForExchange live order lookup"
```

---

### Task 6: `Exchange::EligibilityCalculator` service

**Files:**
- Create: `app/services/exchange/eligibility_calculator.rb`
- Test: `test/services/exchange/eligibility_calculator_test.rb`

**Interfaces:**
- Consumes: the order Hash shape produced by Task 5 (`{ cancelled:, fulfilled_at: }`), `ExchangeConfig#return_window_days`.
- Produces: `Exchange::EligibilityCalculator.new(config).call(order)` → one of `:cancelled`, `:not_fulfilled`, `:return_and_exchange`, `:exchange_only` — consumed by Tasks 12, 14 (views) and controller logic.

- [ ] **Step 1: Write the failing test**

```ruby
require 'test_helper'

class Exchange::EligibilityCalculatorTest < ActiveSupport::TestCase
  def build_config(return_window_days: 7)
    client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
    ExchangeConfig.create!(client: client, return_window_days: return_window_days)
  end

  test 'returns :cancelled when the order was cancelled' do
    result = Exchange::EligibilityCalculator.new(build_config).call(cancelled: true, fulfilled_at: 1.day.ago)
    assert_equal :cancelled, result
  end

  test 'returns :not_fulfilled when there is no fulfillment date' do
    result = Exchange::EligibilityCalculator.new(build_config).call(cancelled: false, fulfilled_at: nil)
    assert_equal :not_fulfilled, result
  end

  test 'returns :return_and_exchange within the return window' do
    result = Exchange::EligibilityCalculator.new(build_config(return_window_days: 7)).call(
      cancelled: false, fulfilled_at: 3.days.ago
    )
    assert_equal :return_and_exchange, result
  end

  test 'returns :return_and_exchange exactly on the last day of the window' do
    result = Exchange::EligibilityCalculator.new(build_config(return_window_days: 7)).call(
      cancelled: false, fulfilled_at: 7.days.ago
    )
    assert_equal :return_and_exchange, result
  end

  test 'returns :exchange_only past the return window' do
    result = Exchange::EligibilityCalculator.new(build_config(return_window_days: 7)).call(
      cancelled: false, fulfilled_at: 8.days.ago
    )
    assert_equal :exchange_only, result
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/exchange/eligibility_calculator_test.rb`
Expected: FAIL — `uninitialized constant Exchange`

- [ ] **Step 3: Write the service**

`app/services/exchange/eligibility_calculator.rb`:
```ruby
module Exchange
  class EligibilityCalculator
    def initialize(config)
      @config = config
    end

    def call(order)
      return :cancelled if order[:cancelled]
      return :not_fulfilled if order[:fulfilled_at].blank?

      days_since_fulfillment = (Date.current - order[:fulfilled_at].to_date).to_i
      days_since_fulfillment <= @config.return_window_days ? :return_and_exchange : :exchange_only
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/exchange/eligibility_calculator_test.rb`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
git add app/services/exchange/eligibility_calculator.rb test/services/exchange/eligibility_calculator_test.rb
git commit -m "feat: add Exchange::EligibilityCalculator"
```

---

### Task 7: `Exchange::LookupThrottle` service

**Files:**
- Create: `app/services/exchange/lookup_throttle.rb`
- Test: `test/services/exchange/lookup_throttle_test.rb`

**Interfaces:**
- Consumes: nothing new (wraps any `ActiveSupport::Cache::Store`-compatible object).
- Produces: `Exchange::LookupThrottle.new(cache:).allow?(key)` → boolean — consumed by Task 12.

- [ ] **Step 1: Write the failing test**

```ruby
require 'test_helper'

class Exchange::LookupThrottleTest < ActiveSupport::TestCase
  test 'allows requests under the limit' do
    throttle = Exchange::LookupThrottle.new(cache: ActiveSupport::Cache::MemoryStore.new)

    9.times { assert throttle.allow?('1.2.3.4') }
  end

  test 'blocks requests once the limit is exceeded' do
    throttle = Exchange::LookupThrottle.new(cache: ActiveSupport::Cache::MemoryStore.new)

    Exchange::LookupThrottle::LIMIT.times { throttle.allow?('1.2.3.4') }

    assert_not throttle.allow?('1.2.3.4')
  end

  test 'tracks different keys independently' do
    throttle = Exchange::LookupThrottle.new(cache: ActiveSupport::Cache::MemoryStore.new)

    Exchange::LookupThrottle::LIMIT.times { throttle.allow?('1.2.3.4') }

    assert throttle.allow?('5.6.7.8')
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/exchange/lookup_throttle_test.rb`
Expected: FAIL — `uninitialized constant Exchange::LookupThrottle`

- [ ] **Step 3: Write the service**

`app/services/exchange/lookup_throttle.rb`:
```ruby
module Exchange
  class LookupThrottle
    LIMIT = 10
    WINDOW = 5.minutes

    def initialize(cache: Rails.cache)
      @cache = cache
    end

    def allow?(key)
      count = @cache.increment("exchange_lookup:#{key}", 1, expires_in: WINDOW)
      count.present? && count <= LIMIT
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/exchange/lookup_throttle_test.rb`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add app/services/exchange/lookup_throttle.rb test/services/exchange/lookup_throttle_test.rb
git commit -m "feat: add Exchange::LookupThrottle rate limiter"
```

---

### Task 8: Fixed-amount support in `Shopify::CreateDiscountCode`

**Files:**
- Modify: `app/models/shopify/create_discount_code.rb`
- Test: `test/services/shopify/create_discount_code_test.rb` (new — no test currently exists for this service)

**Interfaces:**
- Consumes: nothing new.
- Produces: `Shopify::CreateDiscountCode.call(client:, title:, percentage: nil, amount: nil, customer_shopify_id: nil, expires_in: 7.days)` — `amount:` is the new parameter, consumed by Task 9 (`Exchange::Approve`). Existing callers passing `percentage:` keep working unchanged.

- [ ] **Step 1: Write the failing test**

```ruby
require 'test_helper'

class Shopify::CreateDiscountCodeTest < ActiveSupport::TestCase
  def build_client
    Client.create!(
      name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com",
      shopify_shop_url: 'loja-teste.myshopify.com', shopify_access_token: 'token123'
    )
  end

  class FakeRestClient
    def initialize(&block)
      @block = block
    end

    def post(path:, body:)
      OpenStruct.new(body: @block.call(path, body))
    end
  end

  test 'creates a percentage discount and returns the code' do
    fake = FakeRestClient.new do |_path, _body|
      { 'data' => { 'discountCodeBasicCreate' => { 'codeDiscountNode' => {}, 'userErrors' => [] } } }
    end

    ShopifyAPI::Clients::Rest::Admin.stub :new, fake do
      code = Shopify::CreateDiscountCode.call(client: build_client, title: 'Troca', percentage: 10)
      assert_match(/\AREC[A-Z0-9]{8}\z/, code)
    end
  end

  test 'creates a fixed amount discount using discountAmount in the mutation' do
    captured = nil
    fake = FakeRestClient.new do |_path, body|
      captured = body
      { 'data' => { 'discountCodeBasicCreate' => { 'codeDiscountNode' => {}, 'userErrors' => [] } } }
    end

    ShopifyAPI::Clients::Rest::Admin.stub :new, fake do
      code = Shopify::CreateDiscountCode.call(client: build_client, title: 'Troca', amount: 149.9)
      assert code.present?
    end

    value = captured[:variables][:basicCodeDiscount][:customerGets][:value]
    assert_equal 149.9, value[:discountAmount][:amount]
    assert_not value.key?(:percentage)
  end

  test 'returns nil when the API returns userErrors' do
    fake = FakeRestClient.new do |_path, _body|
      { 'data' => { 'discountCodeBasicCreate' => { 'codeDiscountNode' => nil, 'userErrors' => [{ 'message' => 'boom' }] } } }
    end

    ShopifyAPI::Clients::Rest::Admin.stub :new, fake do
      assert_nil Shopify::CreateDiscountCode.call(client: build_client, title: 'Troca', amount: 50)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/shopify/create_discount_code_test.rb`
Expected: FAIL — the fixed-amount test fails because `amount:` isn't accepted / the mutation only ever sends `percentage`

- [ ] **Step 3: Modify the service**

Replace `app/models/shopify/create_discount_code.rb` in full with:
```ruby
# Cria um cupom de desconto (percentual ou valor fixo) na Shopify pro cliente
# informado. Diferente de Shopify::CreateCashbackDiscount (que usa credenciais
# fixas de um único cliente via ENV — um bug pré-existente), este serviço usa
# sempre as credenciais do `client` passado, funcionando pra qualquer loja.
class Shopify::CreateDiscountCode
  def self.call(client:, title:, percentage: nil, amount: nil, customer_shopify_id: nil, expires_in: 7.days)
    session = ShopifyAPI::Auth::Session.new(shop: client.shopify_shop_url, access_token: client.shopify_access_token)
    api_client = ShopifyAPI::Clients::Rest::Admin.new(session: session)

    code = "REC#{SecureRandom.alphanumeric(8).upcase}"
    starts_at = Time.current
    ends_at = starts_at + expires_in

    customer_selection = if customer_shopify_id.present?
                           { customers: { add: [customer_shopify_id] } }
                         else
                           { all: true }
                         end

    value = if amount.present?
              { discountAmount: { amount: amount.to_f, appliesOnEachItem: false } }
            else
              { percentage: percentage.to_f / 100 }
            end

    mutation = <<~GRAPHQL
      mutation discountCodeBasicCreate($basicCodeDiscount: DiscountCodeBasicInput!) {
        discountCodeBasicCreate(basicCodeDiscount: $basicCodeDiscount) {
          codeDiscountNode {
            id
            codeDiscount {
              ... on DiscountCodeBasic {
                codes(first: 1) { nodes { code } }
              }
            }
          }
          userErrors { field message }
        }
      }
    GRAPHQL

    variables = {
      basicCodeDiscount: {
        title: title,
        code: code,
        startsAt: starts_at.iso8601,
        endsAt: ends_at.iso8601,
        customerGets: { value: value, items: { all: true } },
        customerSelection: customer_selection,
        usageLimit: 1
      }
    }

    response = api_client.post(path: 'graphql.json', body: { query: mutation, variables: variables })
    errors = response.body.dig('data', 'discountCodeBasicCreate', 'userErrors')

    return nil if errors.present? && errors.any?

    code
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/shopify/create_discount_code_test.rb`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add app/models/shopify/create_discount_code.rb test/services/shopify/create_discount_code_test.rb
git commit -m "feat: support fixed-amount discounts in Shopify::CreateDiscountCode"
```

---

### Task 9: `Ses::SendEmailService`

**Files:**
- Create: `app/services/ses/send_email_service.rb`
- Test: `test/services/ses/send_email_service_test.rb`

**Interfaces:**
- Consumes: `Client#ses_domain_verified?`, `Client#email_sending_domain` (existing).
- Produces: `Ses::SendEmailService.new(client, ses:).call(to:, subject:, html_body:)` → boolean — consumed by Task 10.

- [ ] **Step 1: Write the failing test**

```ruby
require 'test_helper'

class Ses::SendEmailServiceTest < ActiveSupport::TestCase
  def build_client(verified: true)
    Client.create!(
      name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com",
      email_sending_domain: 'loja.com.br', ses_verification_status: verified ? 'verified' : 'pending'
    )
  end

  test 'sends through SES using the client sending domain and returns true' do
    fake_ses = Minitest::Mock.new
    fake_ses.expect(:send_email, true) do |args|
      args[:from_email_address].end_with?('@loja.com.br') &&
        args[:destination][:to_addresses] == ['ana@example.com'] &&
        args[:content][:simple][:subject][:data] == 'Assunto' &&
        args[:content][:simple][:body][:html][:data] == '<p>Corpo</p>'
    end

    result = Ses::SendEmailService.new(build_client, ses: fake_ses).call(
      to: 'ana@example.com', subject: 'Assunto', html_body: '<p>Corpo</p>'
    )

    assert result
    fake_ses.verify
  end

  test 'returns false without calling SES when the domain is not verified' do
    fake_ses = Minitest::Mock.new

    result = Ses::SendEmailService.new(build_client(verified: false), ses: fake_ses).call(
      to: 'ana@example.com', subject: 'Assunto', html_body: '<p>Corpo</p>'
    )

    assert_equal false, result
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/ses/send_email_service_test.rb`
Expected: FAIL — `uninitialized constant Ses::SendEmailService`

- [ ] **Step 3: Write the service**

`app/services/ses/send_email_service.rb`:
```ruby
module Ses
  class SendEmailService
    def initialize(client, ses: Aws::SESV2::Client.new)
      @client = client
      @ses = ses
    end

    def call(to:, subject:, html_body:)
      return false unless @client.ses_domain_verified?

      @ses.send_email(
        from_email_address: "naoresponda@#{@client.email_sending_domain}",
        destination: { to_addresses: [to] },
        content: {
          simple: {
            subject: { data: subject },
            body: { html: { data: html_body } }
          }
        }
      )
      true
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/ses/send_email_service_test.rb`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add app/services/ses/send_email_service.rb test/services/ses/send_email_service_test.rb
git commit -m "feat: add Ses::SendEmailService"
```

---

### Task 10: `SendExchangeEmailJob`

**Files:**
- Create: `app/jobs/send_exchange_email_job.rb`
- Test: `test/jobs/send_exchange_email_job_test.rb`

**Interfaces:**
- Consumes: `ExchangeConfig`'s 8 subject/body fields (Task 2), `ExchangeRequest#customer_email/#customer_name/#shopify_order_number/#coupon_code` (Task 4), `Ses::SendEmailService` (Task 9).
- Produces: `SendExchangeEmailJob.perform_later(exchange_request_id:, kind:)` where `kind` is one of `'requested'`, `'approved'`, `'rejected'`, `'completed'` — consumed by Tasks 11, 12, 14.

- [ ] **Step 1: Write the failing test**

```ruby
require 'test_helper'

class SendExchangeEmailJobTest < ActiveSupport::TestCase
  def build_request(coupon_code: nil)
    client = Client.create!(
      name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com",
      email_sending_domain: 'loja.com.br', ses_verification_status: 'verified'
    )
    ExchangeConfig.create!(
      client: client,
      requested_email_subject: 'Recebemos sua solicitação',
      requested_email_body: 'Olá {{customer_name}}, recebemos o pedido {{order_number}}.',
      approved_email_subject: 'Troca aprovada',
      approved_email_body: 'Use o cupom {{coupon_code}} na sua próxima compra.'
    )
    ExchangeRequest.create!(
      client: client, shopify_order_id: '1', shopify_order_number: '#1001',
      customer_email: 'ana@example.com', customer_name: 'Ana', coupon_code: coupon_code
    )
  end

  test 'sends the requested e-mail with placeholders interpolated' do
    request = build_request
    fake_service = Minitest::Mock.new
    fake_service.expect(:call, true) do |args|
      args[:to] == 'ana@example.com' &&
        args[:subject] == 'Recebemos sua solicitação' &&
        args[:html_body] == 'Olá Ana, recebemos o pedido #1001.'
    end

    Ses::SendEmailService.stub :new, fake_service do
      SendExchangeEmailJob.perform_now(exchange_request_id: request.id, kind: 'requested')
    end

    fake_service.verify
  end

  test 'interpolates the coupon code on the approved e-mail' do
    request = build_request(coupon_code: 'RECABC12345')
    fake_service = Minitest::Mock.new
    fake_service.expect(:call, true) do |args|
      args[:html_body] == 'Use o cupom RECABC12345 na sua próxima compra.'
    end

    Ses::SendEmailService.stub :new, fake_service do
      SendExchangeEmailJob.perform_now(exchange_request_id: request.id, kind: 'approved')
    end

    fake_service.verify
  end

  test 'does nothing when the client has no ExchangeConfig' do
    client = Client.create!(name: 'Sem config', email: "sem-config-#{SecureRandom.hex(4)}@example.com")
    request = ExchangeRequest.create!(
      client: client, shopify_order_id: '1', shopify_order_number: '#1001', customer_email: 'ana@example.com'
    )

    assert_nothing_raised do
      SendExchangeEmailJob.perform_now(exchange_request_id: request.id, kind: 'requested')
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/jobs/send_exchange_email_job_test.rb`
Expected: FAIL — `uninitialized constant SendExchangeEmailJob`

- [ ] **Step 3: Write the job**

`app/jobs/send_exchange_email_job.rb`:
```ruby
class SendExchangeEmailJob < ApplicationJob
  queue_as :default

  SUBJECT_FIELDS = {
    'requested' => :requested_email_subject,
    'approved' => :approved_email_subject,
    'rejected' => :rejected_email_subject,
    'completed' => :completed_email_subject
  }.freeze

  BODY_FIELDS = {
    'requested' => :requested_email_body,
    'approved' => :approved_email_body,
    'rejected' => :rejected_email_body,
    'completed' => :completed_email_body
  }.freeze

  def perform(exchange_request_id:, kind:)
    exchange_request = ExchangeRequest.find(exchange_request_id)
    client = exchange_request.client
    config = client.exchange_config

    unless config
      Rails.logger.warn "[SendExchangeEmailJob] Client #{client.id} não tem ExchangeConfig — pulando envio"
      return
    end

    Ses::SendEmailService.new(client).call(
      to: exchange_request.customer_email,
      subject: interpolate(config.public_send(SUBJECT_FIELDS.fetch(kind)), exchange_request),
      html_body: interpolate(config.public_send(BODY_FIELDS.fetch(kind)), exchange_request)
    )
  rescue StandardError => e
    Rails.logger.error "[SendExchangeEmailJob] Falha para exchange_request #{exchange_request_id}: #{e.message}"
  end

  private

  def interpolate(text, exchange_request)
    text.to_s
        .gsub('{{customer_name}}', exchange_request.customer_name.to_s)
        .gsub('{{order_number}}', exchange_request.shopify_order_number.to_s)
        .gsub('{{coupon_code}}', exchange_request.coupon_code.to_s)
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/jobs/send_exchange_email_job_test.rb`
Expected: PASS (3 tests) — note `Ses::SendEmailService.new(client).call(...)` still runs against the real (unverified in these fixtures except where explicitly set) service; since the job stubs `Ses::SendEmailService.stub :new, fake_service`, the real `ses_domain_verified?` gate inside the service is bypassed entirely by the stub, which is intentional — this test is about the job's templating/dispatch, not about SES verification (already covered by Task 9's tests).

- [ ] **Step 5: Commit**

```bash
git add app/jobs/send_exchange_email_job.rb test/jobs/send_exchange_email_job_test.rb
git commit -m "feat: add SendExchangeEmailJob"
```

---

### Task 11: `Exchange::Approve` service

**Files:**
- Create: `app/services/exchange/approve.rb`
- Test: `test/services/exchange/approve_test.rb`

**Interfaces:**
- Consumes: `ExchangeRequest#troca_total` (Task 4), `Shopify::CreateDiscountCode.call` (Task 8), `SendExchangeEmailJob` (Task 10), `ExchangeConfig#coupon_validity_days` (Task 2).
- Produces: `Exchange::Approve.new(exchange_request).call` → sets `status: approved` (+ `coupon_code` when applicable) and enqueues the `approved` e-mail — consumed by Task 14.

- [ ] **Step 1: Write the failing test**

```ruby
require 'test_helper'

class Exchange::ApproveTest < ActiveSupport::TestCase
  def build_request
    client = Client.create!(
      name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com",
      shopify_shop_url: 'loja-teste.myshopify.com', shopify_access_token: 'token123'
    )
    ExchangeConfig.create!(client: client, coupon_validity_days: 15)
    ExchangeRequest.create!(
      client: client, shopify_order_id: '1', shopify_order_number: '#1001', customer_email: 'ana@example.com'
    )
  end

  test 'approves and generates a coupon for the troca items total' do
    request = build_request
    request.exchange_request_items.create!(product_name: 'A', quantity: 2, price: 50, kind: :troca)
    request.exchange_request_items.create!(product_name: 'B', quantity: 1, price: 30, kind: :devolucao)

    captured = nil
    Shopify::CreateDiscountCode.stub :call, ->(**kwargs) { captured = kwargs; 'RECABC12345' } do
      Exchange::Approve.new(request).call
    end

    request.reload
    assert request.approved?
    assert_equal 'RECABC12345', request.coupon_code
    assert_equal 100.0, captured[:amount]
    assert_equal 15.days, captured[:expires_in]
  end

  test 'approves without generating a coupon when there is no troca item' do
    request = build_request
    request.exchange_request_items.create!(product_name: 'B', quantity: 1, price: 30, kind: :devolucao)

    Shopify::CreateDiscountCode.stub :call, ->(**) { raise 'should not be called' } do
      Exchange::Approve.new(request).call
    end

    request.reload
    assert request.approved?
    assert_nil request.coupon_code
  end

  test 'enqueues the approved e-mail job' do
    request = build_request

    assert_enqueued_with(job: SendExchangeEmailJob, args: [{ exchange_request_id: request.id, kind: 'approved' }]) do
      Exchange::Approve.new(request).call
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/exchange/approve_test.rb`
Expected: FAIL — `uninitialized constant Exchange::Approve`

- [ ] **Step 3: Write the service**

`app/services/exchange/approve.rb`:
```ruby
module Exchange
  class Approve
    def initialize(exchange_request)
      @exchange_request = exchange_request
    end

    def call
      @exchange_request.update!(status: :approved, coupon_code: generate_coupon)
      SendExchangeEmailJob.perform_later(exchange_request_id: @exchange_request.id, kind: 'approved')
      @exchange_request
    end

    private

    def generate_coupon
      total = @exchange_request.troca_total
      return nil if total <= 0

      config = @exchange_request.client.exchange_config

      Shopify::CreateDiscountCode.call(
        client: @exchange_request.client,
        title: "Troca - Pedido #{@exchange_request.shopify_order_number}",
        amount: total,
        expires_in: config.coupon_validity_days.days
      )
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/exchange/approve_test.rb`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add app/services/exchange/approve.rb test/services/exchange/approve_test.rb
git commit -m "feat: add Exchange::Approve to generate coupons and notify on approval"
```

---

### Task 12: Public wizard — `Widget::ExchangesController` + views + routes

**Files:**
- Create: `app/controllers/widget/exchanges_controller.rb`
- Create: `app/views/widget/exchanges/new.html.erb`
- Create: `app/views/widget/exchanges/lookup.html.erb`
- Create: `app/views/widget/exchanges/confirmation.html.erb`
- Modify: `config/routes.rb`
- Test: `test/controllers/widget/exchanges_controller_test.rb`

**Interfaces:**
- Consumes: `Shopify::FindOrderForExchange.call` (Task 5), `Exchange::EligibilityCalculator` (Task 6), `Exchange::LookupThrottle` (Task 7), `ExchangeConfig#public_token/#active?` (Task 2), `ExchangeRequest`/`ExchangeRequestItem` (Tasks 3, 4), `SendExchangeEmailJob` (Task 10).
- Produces: the public routes `new_exchange_path(token)`, `lookup_exchange_path(token)`, `exchange_path(token)` — no other task depends on these directly.

- [ ] **Step 1: Write the failing test**

```ruby
require 'test_helper'

class Widget::ExchangesControllerTest < ActionDispatch::IntegrationTest
  def build_client
    Client.create!(
      name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com",
      shopify_shop_url: 'loja-teste.myshopify.com', shopify_access_token: 'token123'
    )
  end

  def build_config(client, active: true)
    ExchangeConfig.create!(client: client, active: active, company_name: 'Loja Teste')
  end

  def shopify_order(overrides = {})
    {
      id: '555001', number: '#1001', email: 'ana@example.com', cancelled: false,
      fulfilled_at: 2.days.ago,
      items: [{ sku: 'SKU-1', product_name: 'Camiseta', variant_title: 'P', quantity: 1, price: 99.9 }]
    }.merge(overrides)
  end

  test 'new renders the lookup form for an active config' do
    config = build_config(build_client)

    get new_exchange_path(config.public_token)

    assert_response :success
  end

  test 'new returns 404 for an unknown token' do
    get new_exchange_path('does-not-exist')
    assert_response :not_found
  end

  test 'new returns 404 for an inactive config' do
    config = build_config(build_client, active: false)
    get new_exchange_path(config.public_token)
    assert_response :not_found
  end

  test 'lookup shows the order items when found' do
    config = build_config(build_client)

    Exchange::LookupThrottle.stub :new, OpenStruct.new(allow?: true) do
      Shopify::FindOrderForExchange.stub :call, shopify_order do
        post lookup_exchange_path(config.public_token), params: { order_number: '1001', email: 'ana@example.com' }
      end
    end

    assert_response :success
    assert_match 'Camiseta', response.body
  end

  test 'lookup re-renders the form with an error when the order is not found' do
    config = build_config(build_client)

    Exchange::LookupThrottle.stub :new, OpenStruct.new(allow?: true) do
      Shopify::FindOrderForExchange.stub :call, nil do
        post lookup_exchange_path(config.public_token), params: { order_number: '9999', email: 'ana@example.com' }
      end
    end

    assert_response :unprocessable_entity
  end

  test 'create persists the request with only the eligible kind and enqueues the requested e-mail' do
    config = build_config(build_client)

    assert_enqueued_with(job: SendExchangeEmailJob) do
      Exchange::LookupThrottle.stub :new, OpenStruct.new(allow?: true) do
        Shopify::FindOrderForExchange.stub :call, shopify_order do
          post exchange_path(config.public_token), params: {
            order_number: '1001', email: 'ana@example.com', customer_name: 'Ana',
            items: [{ sku: 'SKU-1', kind: 'troca', reason: 'Tamanho errado' }]
          }
        end
      end
    end

    assert_response :success
    request = ExchangeRequest.last
    assert_equal 'ana@example.com', request.customer_email
    assert_equal 1, request.exchange_request_items.count
    assert_equal 'Camiseta', request.exchange_request_items.first.product_name
  end

  test 'create ignores a devolucao selection when the order is past the return window' do
    config = build_config(build_client)
    old_order = shopify_order(fulfilled_at: 30.days.ago)

    Exchange::LookupThrottle.stub :new, OpenStruct.new(allow?: true) do
      Shopify::FindOrderForExchange.stub :call, old_order do
        post exchange_path(config.public_token), params: {
          order_number: '1001', email: 'ana@example.com',
          items: [{ sku: 'SKU-1', kind: 'devolucao', reason: 'Não gostei' }]
        }
      end
    end

    assert_response :unprocessable_entity
    assert_equal 0, ExchangeRequest.count
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/widget/exchanges_controller_test.rb`
Expected: FAIL — routes/controller don't exist yet

- [ ] **Step 3: Add routes**

In `config/routes.rb`, inside the existing `namespace :widget do ... end` block, after the `popup` routes:
```ruby
    get  'exchanges/:token',        to: 'exchanges#new',    as: :new_exchange
    post 'exchanges/:token/lookup', to: 'exchanges#lookup', as: :lookup_exchange
    post 'exchanges/:token',        to: 'exchanges#create', as: :exchange
```

- [ ] **Step 4: Write the controller**

`app/controllers/widget/exchanges_controller.rb`:
```ruby
module Widget
  class ExchangesController < ApplicationController
    skip_before_action :authenticate_user!, :redirect_affiliate_to_events!
    protect_from_forgery with: :null_session

    before_action :set_config
    before_action :require_active_config!

    def new; end

    def lookup
      @order = find_order
      return render_not_found_error unless @order

      @eligibility = Exchange::EligibilityCalculator.new(@config).call(@order)
      @order_number = params[:order_number]
      @email = params[:email]
    end

    def create
      @order = find_order
      return render_not_found_error(view: :new) unless @order

      @eligibility = Exchange::EligibilityCalculator.new(@config).call(@order)
      @order_number = params[:order_number]
      @email = params[:email]
      selected_items = build_selected_items

      if selected_items.empty?
        flash.now[:alert] = 'Selecione ao menos um item elegível.'
        render :lookup, status: :unprocessable_entity
        return
      end

      exchange_request = @config.client.exchange_requests.create!(
        shopify_order_id: @order[:id], shopify_order_number: @order[:number],
        customer_email: params[:email], customer_name: params[:customer_name]
      )
      selected_items.each { |item| exchange_request.exchange_request_items.create!(item) }

      SendExchangeEmailJob.perform_later(exchange_request_id: exchange_request.id, kind: 'requested')
    end

    private

    def set_config
      @config = ExchangeConfig.find_by(public_token: params[:token])
    end

    def require_active_config!
      render plain: 'Não encontrado', status: :not_found unless @config&.active?
    end

    def render_not_found_error(view: :new)
      flash.now[:alert] = 'Pedido não encontrado. Confira o número do pedido e o e-mail informados.'
      render view, status: :unprocessable_entity
    end

    def find_order
      return nil unless Exchange::LookupThrottle.new.allow?(request.remote_ip)

      Shopify::FindOrderForExchange.call(client: @config.client, order_number: params[:order_number], email: params[:email])
    end

    def build_selected_items
      allowed_kinds = @eligibility == :return_and_exchange ? %w[troca devolucao] : ['troca']

      Array(params[:items]).filter_map do |raw|
        raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
        source = @order[:items].find { |item| item[:sku] == raw['sku'] }
        next unless source
        next unless allowed_kinds.include?(raw['kind'])

        source.merge(kind: raw['kind'], reason: raw['reason'])
      end
    end
  end
end
```

- [ ] **Step 5: Write the views**

`app/views/widget/exchanges/new.html.erb`:
```erb
<% title 'Central de Trocas e Devoluções' %>

<div class="exchange-wizard">
  <div class="exchange-wizard__card">
    <% if @config.logo.attached? %>
      <%= image_tag @config.logo, class: 'exchange-wizard__logo' %>
    <% end %>
    <h1 class="exchange-wizard__title"><%= @config.company_name %></h1>
    <% if @config.instructions.present? %>
      <p class="exchange-wizard__instructions"><%= simple_format(@config.instructions) %></p>
    <% end %>

    <%= form_with url: lookup_exchange_path(@config.public_token), method: :post, local: true do %>
      <div class="exchange-wizard__field">
        <label for="order_number">Número do pedido</label>
        <input type="text" name="order_number" id="order_number" required placeholder="#1001">
      </div>
      <div class="exchange-wizard__field">
        <label for="email">E-mail usado na compra</label>
        <input type="email" name="email" id="email" required>
      </div>
      <button type="submit" class="exchange-wizard__submit" style="background: <%= @config.accent_color %>">
        Buscar pedido
      </button>
    <% end %>
  </div>
</div>
```

`app/views/widget/exchanges/lookup.html.erb`:
```erb
<% title 'Central de Trocas e Devoluções' %>

<div class="exchange-wizard">
  <div class="exchange-wizard__card">
    <h1 class="exchange-wizard__title">Pedido <%= @order[:number] %></h1>

    <% case @eligibility
       when :not_fulfilled %>
      <p class="exchange-wizard__notice">Esse pedido ainda não foi enviado — assim que for despachado você poderá solicitar troca ou devolução aqui.</p>
    <% when :cancelled %>
      <p class="exchange-wizard__notice">Esse pedido foi cancelado e não é elegível para troca ou devolução.</p>
    <% else %>
      <% if @eligibility == :exchange_only %>
        <p class="exchange-wizard__notice">O prazo de devolução desse pedido já passou — só é possível solicitar troca.</p>
      <% end %>

      <%= form_with url: exchange_path(@config.public_token), method: :post, local: true do %>
        <input type="hidden" name="order_number" value="<%= @order_number %>">
        <input type="hidden" name="email" value="<%= @email %>">
        <div class="exchange-wizard__field">
          <label for="customer_name">Seu nome</label>
          <input type="text" name="customer_name" id="customer_name">
        </div>

        <% @order[:items].each_with_index do |item, index| %>
          <div class="exchange-wizard__item">
            <p><strong><%= item[:product_name] %></strong> <%= item[:variant_title] %> — qtd. <%= item[:quantity] %></p>
            <label>
              <input type="checkbox" name="items[<%= index %>][sku]" value="<%= item[:sku] %>" class="exchange-wizard__item-check">
              Selecionar este item
            </label>
            <select name="items[<%= index %>][kind]">
              <option value="troca">Troca</option>
              <% if @eligibility == :return_and_exchange %>
                <option value="devolucao">Devolução</option>
              <% end %>
            </select>
            <input type="text" name="items[<%= index %>][reason]" placeholder="Motivo">
          </div>
        <% end %>

        <button type="submit" class="exchange-wizard__submit" style="background: <%= @config.accent_color %>">
          Enviar solicitação
        </button>
      <% end %>
    <% end %>
  </div>
</div>
```

`app/views/widget/exchanges/confirmation.html.erb`:
```erb
<% title 'Solicitação enviada' %>

<div class="exchange-wizard">
  <div class="exchange-wizard__card">
    <h1 class="exchange-wizard__title">Solicitação enviada!</h1>
    <p>Você vai receber um e-mail em <strong><%= params[:email] %></strong> com a confirmação e os próximos passos.</p>
  </div>
</div>
```

Note: the unchecked-item problem — a plain HTML checkbox that's left unchecked simply isn't submitted, so `items[<index>][sku]` won't be present for that index and `build_selected_items` correctly skips it via `source = @order[:items].find { ... }` returning `nil` when `raw['sku']` is blank/absent. No extra JS is required for v1.

- [ ] **Step 6: Run test to verify it passes**

Run: `bin/rails test test/controllers/widget/exchanges_controller_test.rb`
Expected: PASS (7 tests)

- [ ] **Step 7: Commit**

```bash
git add config/routes.rb app/controllers/widget/exchanges_controller.rb \
        app/views/widget/exchanges/new.html.erb app/views/widget/exchanges/lookup.html.erb \
        app/views/widget/exchanges/confirmation.html.erb \
        test/controllers/widget/exchanges_controller_test.rb
git commit -m "feat: add public exchange/return request wizard"
```

---

### Task 13: Admin config screen — `ExchangeConfigsController` + view + route

**Files:**
- Create: `app/controllers/exchange_configs_controller.rb`
- Create: `app/views/exchange_configs/edit.html.erb`
- Modify: `config/routes.rb`
- Test: `test/controllers/exchange_configs_controller_test.rb`

**Interfaces:**
- Consumes: `ClientScoped` concern (existing), `ExchangeConfig` (Task 2).
- Produces: `edit_exchange_config_path` / `exchange_config_path` — consumed by Task 15 (sidebar).

- [ ] **Step 1: Write the failing test**

```ruby
require 'test_helper'

class ExchangeConfigsControllerTest < ActionDispatch::IntegrationTest
  def build_client
    Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
  end

  def build_user(client:)
    Profile.find_or_create_by!(id: Profile::USER) { |p| p.name = 'User' }
    User.create!(
      name: 'User', email: "user-#{SecureRandom.hex(4)}@example.com",
      password: 'password123', password_confirmation: 'password123', profile_id: Profile::USER, client: client
    )
  end

  test 'edit builds a new config when none exists yet' do
    sign_in build_user(client: build_client)
    get edit_exchange_config_path
    assert_response :success
  end

  test 'update saves the branding, window and e-mail fields' do
    client = build_client
    sign_in build_user(client: client)

    patch exchange_config_path, params: {
      exchange_config: {
        active: '1', company_name: 'Loja Teste', return_window_days: 10, coupon_validity_days: 20,
        requested_email_subject: 'Recebemos!', requested_email_body: 'Olá {{customer_name}}'
      }
    }

    assert_redirected_to edit_exchange_config_path
    config = client.reload.exchange_config
    assert config.active?
    assert_equal 10, config.return_window_days
    assert_equal 'Recebemos!', config.requested_email_subject
  end

  test 'update re-renders the form when invalid' do
    sign_in build_user(client: build_client)

    patch exchange_config_path, params: { exchange_config: { active: '1', company_name: '' } }

    assert_response :unprocessable_entity
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/exchange_configs_controller_test.rb`
Expected: FAIL — controller/route don't exist

- [ ] **Step 3: Add the route**

In `config/routes.rb`, inside the `/crm` scope, near `resource :popup, only: %i[edit update]`:
```ruby
    resource :exchange_config, only: %i[edit update]
```

- [ ] **Step 4: Write the controller**

`app/controllers/exchange_configs_controller.rb`:
```ruby
class ExchangeConfigsController < ApplicationController
  include ClientScoped

  before_action :set_client
  before_action :ensure_client!
  before_action :load_exchange_config

  def edit; end

  def update
    @exchange_config.logo.purge if params.dig(:exchange_config, :remove_logo) == '1'

    if @exchange_config.update(exchange_config_params)
      redirect_to edit_exchange_config_path, notice: 'Configuração salva com sucesso.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def ensure_client!
    redirect_to crm_path, alert: 'Nenhum cliente selecionado.' unless @client
  end

  def load_exchange_config
    @exchange_config = @client.exchange_config || @client.build_exchange_config
  end

  def exchange_config_params
    params.require(:exchange_config).permit(
      :active, :company_name, :accent_color, :instructions, :return_window_days, :coupon_validity_days, :logo,
      :requested_email_subject, :requested_email_body,
      :approved_email_subject, :approved_email_body,
      :rejected_email_subject, :rejected_email_body,
      :completed_email_subject, :completed_email_body
    )
  end
end
```

- [ ] **Step 5: Write the view**

`app/views/exchange_configs/edit.html.erb`:
```erb
<% title 'Trocas e Devoluções' %>

<div class="users-form-page">
  <div class="crm-card users-form-page__card">
    <div class="users-form-page__header">
      <div>
        <h2 class="users-form-page__title">Configuração de Trocas e Devoluções</h2>
        <p class="users-form-page__subtitle"><%= @client.name %></p>
      </div>
    </div>

    <% if @exchange_config.errors.any? %>
      <div class="users-form-page__errors">
        <ul>
          <% @exchange_config.errors.full_messages.each do |msg| %>
            <li><%= msg %></li>
          <% end %>
        </ul>
      </div>
    <% end %>

    <%= form_for @exchange_config, as: :exchange_config, url: exchange_config_path, method: :patch,
                 html: { multipart: true } do |form| %>
      <div class="users-form-page__body">
        <%= form.label :active, 'Ativo' %>
        <%= form.check_box :active %>

        <%= form.label :company_name, 'Nome da empresa' %>
        <%= form.text_field :company_name %>

        <%= form.label :logo, 'Logo' %>
        <%= form.file_field :logo %>
        <% if @exchange_config.logo.attached? %>
          <%= image_tag @exchange_config.logo, style: 'max-height: 60px;' %>
          <label><%= check_box_tag 'exchange_config[remove_logo]', '1' %> Remover logo</label>
        <% end %>

        <%= form.label :accent_color, 'Cor de destaque' %>
        <%= form.text_field :accent_color %>

        <%= form.label :instructions, 'Instruções exibidas na página pública' %>
        <%= form.text_area :instructions %>

        <%= form.label :return_window_days, 'Prazo (dias) para permitir devolução' %>
        <%= form.number_field :return_window_days %>

        <%= form.label :coupon_validity_days, 'Validade (dias) do cupom gerado na aprovação' %>
        <%= form.number_field :coupon_validity_days %>

        <h3>E-mail — solicitação recebida</h3>
        <%= form.text_field :requested_email_subject, placeholder: 'Assunto' %>
        <%= form.text_area :requested_email_body, placeholder: 'Corpo — use {{customer_name}} e {{order_number}}' %>

        <h3>E-mail — aprovado</h3>
        <%= form.text_field :approved_email_subject, placeholder: 'Assunto' %>
        <%= form.text_area :approved_email_body, placeholder: 'Corpo — use {{customer_name}}, {{order_number}} e {{coupon_code}}' %>

        <h3>E-mail — rejeitado</h3>
        <%= form.text_field :rejected_email_subject, placeholder: 'Assunto' %>
        <%= form.text_area :rejected_email_body, placeholder: 'Corpo — use {{customer_name}} e {{order_number}}' %>

        <h3>E-mail — concluído</h3>
        <%= form.text_field :completed_email_subject, placeholder: 'Assunto' %>
        <%= form.text_area :completed_email_body, placeholder: 'Corpo — use {{customer_name}} e {{order_number}}' %>
      </div>

      <div class="users-form-page__footer">
        <%= form.submit 'Salvar', class: 'crm-btn crm-btn--primary' %>
      </div>
    <% end %>

    <% if @exchange_config.persisted? && @exchange_config.public_token.present? %>
      <p>Link público: <code><%= new_exchange_url(@exchange_config.public_token) %></code></p>
    <% end %>
  </div>
</div>
```

- [ ] **Step 6: Run test to verify it passes**

Run: `bin/rails test test/controllers/exchange_configs_controller_test.rb`
Expected: PASS (3 tests)

- [ ] **Step 7: Commit**

```bash
git add config/routes.rb app/controllers/exchange_configs_controller.rb \
        app/views/exchange_configs/edit.html.erb test/controllers/exchange_configs_controller_test.rb
git commit -m "feat: add exchange config admin screen"
```

---

### Task 14: Admin review screen — `ExchangeRequestsController` + views + route

**Files:**
- Create: `app/controllers/exchange_requests_controller.rb`
- Create: `app/views/exchange_requests/index.html.erb`
- Create: `app/views/exchange_requests/show.html.erb`
- Modify: `config/routes.rb`
- Test: `test/controllers/exchange_requests_controller_test.rb`

**Interfaces:**
- Consumes: `ClientScoped` (existing), `ExchangeRequest`/`ExchangeRequestItem` (Tasks 3, 4), `Exchange::Approve` (Task 11), `SendExchangeEmailJob` (Task 10).
- Produces: `exchange_requests_path` / `exchange_request_path` — consumed by Task 15 (sidebar).

- [ ] **Step 1: Write the failing test**

```ruby
require 'test_helper'

class ExchangeRequestsControllerTest < ActionDispatch::IntegrationTest
  def build_client
    Client.create!(
      name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com",
      shopify_shop_url: 'loja-teste.myshopify.com', shopify_access_token: 'token123'
    )
  end

  def build_user(client:)
    Profile.find_or_create_by!(id: Profile::USER) { |p| p.name = 'User' }
    User.create!(
      name: 'User', email: "user-#{SecureRandom.hex(4)}@example.com",
      password: 'password123', password_confirmation: 'password123', profile_id: Profile::USER, client: client
    )
  end

  def build_request(client)
    ExchangeConfig.create!(client: client, coupon_validity_days: 30)
    ExchangeRequest.create!(
      client: client, shopify_order_id: '1', shopify_order_number: '#1001', customer_email: 'ana@example.com'
    )
  end

  test 'index lists the client requests' do
    client = build_client
    build_request(client)
    sign_in build_user(client: client)

    get exchange_requests_path

    assert_response :success
    assert_match '#1001', response.body
  end

  test 'show displays the request items' do
    client = build_client
    request = build_request(client)
    request.exchange_request_items.create!(product_name: 'Camiseta', quantity: 1, price: 50, kind: :troca)
    sign_in build_user(client: client)

    get exchange_request_path(request)

    assert_response :success
    assert_match 'Camiseta', response.body
  end

  test 'update with status approved calls Exchange::Approve and enqueues the e-mail' do
    client = build_client
    request = build_request(client)
    request.exchange_request_items.create!(product_name: 'Camiseta', quantity: 1, price: 50, kind: :troca)
    sign_in build_user(client: client)

    Shopify::CreateDiscountCode.stub :call, 'RECABC12345' do
      assert_enqueued_with(job: SendExchangeEmailJob, args: [{ exchange_request_id: request.id, kind: 'approved' }]) do
        patch exchange_request_path(request), params: { status: 'approved' }
      end
    end

    assert request.reload.approved?
    assert_equal 'RECABC12345', request.coupon_code
  end

  test 'update with status rejected enqueues the rejected e-mail' do
    client = build_client
    request = build_request(client)
    sign_in build_user(client: client)

    assert_enqueued_with(job: SendExchangeEmailJob, args: [{ exchange_request_id: request.id, kind: 'rejected' }]) do
      patch exchange_request_path(request), params: { status: 'rejected' }
    end

    assert request.reload.rejected?
  end

  test 'update with status completed enqueues the completed e-mail' do
    client = build_client
    request = build_request(client)
    request.update!(status: :approved)
    sign_in build_user(client: client)

    assert_enqueued_with(job: SendExchangeEmailJob, args: [{ exchange_request_id: request.id, kind: 'completed' }]) do
      patch exchange_request_path(request), params: { status: 'completed' }
    end

    assert request.reload.completed?
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/exchange_requests_controller_test.rb`
Expected: FAIL — controller/route don't exist

- [ ] **Step 3: Add the route**

In `config/routes.rb`, inside the `/crm` scope, right after `resource :exchange_config, only: %i[edit update]`:
```ruby
    resources :exchange_requests, only: %i[index show update]
```

- [ ] **Step 4: Write the controller**

`app/controllers/exchange_requests_controller.rb`:
```ruby
class ExchangeRequestsController < ApplicationController
  include ClientScoped

  before_action :set_client
  before_action :ensure_client!
  before_action :set_exchange_request, only: %i[show update]

  def index
    scope = @client.exchange_requests.includes(:exchange_request_items).order(created_at: :desc)
    @status_filter = params[:status].presence
    @exchange_requests = @status_filter.present? ? scope.where(status: @status_filter) : scope
  end

  def show; end

  def update
    case params[:status]
    when 'approved'
      Exchange::Approve.new(@exchange_request).call
    when 'rejected'
      @exchange_request.update!(status: :rejected)
      SendExchangeEmailJob.perform_later(exchange_request_id: @exchange_request.id, kind: 'rejected')
    when 'completed'
      @exchange_request.update!(status: :completed)
      SendExchangeEmailJob.perform_later(exchange_request_id: @exchange_request.id, kind: 'completed')
    end

    @exchange_request.update!(internal_notes: params[:internal_notes]) if params[:internal_notes].present?

    redirect_to exchange_request_path(@exchange_request), notice: 'Solicitação atualizada.'
  end

  private

  def ensure_client!
    redirect_to crm_path, alert: 'Nenhum cliente selecionado.' unless @client
  end

  def set_exchange_request
    @exchange_request = @client.exchange_requests.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to exchange_requests_path, alert: 'Solicitação não encontrada.'
  end
end
```

- [ ] **Step 5: Write the views**

`app/views/exchange_requests/index.html.erb`:
```erb
<% title 'Trocas e Devoluções' %>

<div class="crm-card">
  <table class="crm-table">
    <thead>
      <tr>
        <th>Pedido</th>
        <th>Cliente</th>
        <th>Status</th>
        <th>Criado em</th>
      </tr>
    </thead>
    <tbody>
      <% @exchange_requests.each do |request| %>
        <tr>
          <td><%= link_to request.shopify_order_number, exchange_request_path(request) %></td>
          <td><%= request.customer_name.presence || request.customer_email %></td>
          <td><%= request.status %></td>
          <td><%= l request.created_at, format: :short rescue request.created_at %></td>
        </tr>
      <% end %>
    </tbody>
  </table>
</div>
```

`app/views/exchange_requests/show.html.erb`:
```erb
<% title "Solicitação #{@exchange_request.shopify_order_number}" %>

<div class="crm-card">
  <h2>Pedido <%= @exchange_request.shopify_order_number %></h2>
  <p>Cliente: <%= @exchange_request.customer_name %> — <%= @exchange_request.customer_email %></p>
  <p>Status atual: <strong><%= @exchange_request.status %></strong></p>
  <% if @exchange_request.coupon_code.present? %>
    <p>Cupom gerado: <code><%= @exchange_request.coupon_code %></code></p>
  <% end %>

  <table class="crm-table">
    <thead>
      <tr><th>Produto</th><th>Variante</th><th>Qtd.</th><th>Preço</th><th>Tipo</th><th>Motivo</th></tr>
    </thead>
    <tbody>
      <% @exchange_request.exchange_request_items.each do |item| %>
        <tr>
          <td><%= item.product_name %></td>
          <td><%= item.variant_title %></td>
          <td><%= item.quantity %></td>
          <td><%= number_to_currency item.price %></td>
          <td><%= item.kind %></td>
          <td><%= item.reason %></td>
        </tr>
      <% end %>
    </tbody>
  </table>

  <% if @exchange_request.pending? %>
    <%= button_to 'Aprovar', exchange_request_path(@exchange_request), method: :patch,
                  params: { status: 'approved' }, class: 'crm-btn crm-btn--primary' %>
    <%= button_to 'Rejeitar', exchange_request_path(@exchange_request), method: :patch,
                  params: { status: 'rejected' }, class: 'crm-btn crm-btn--danger' %>
  <% elsif @exchange_request.approved? %>
    <%= button_to 'Marcar como concluída', exchange_request_path(@exchange_request), method: :patch,
                  params: { status: 'completed' }, class: 'crm-btn crm-btn--primary' %>
  <% end %>

  <%= form_with url: exchange_request_path(@exchange_request), method: :patch, local: true do %>
    <label>Nota interna</label>
    <%= text_area_tag 'internal_notes', @exchange_request.internal_notes %>
    <%= submit_tag 'Salvar nota' %>
  <% end %>
</div>
```

- [ ] **Step 6: Run test to verify it passes**

Run: `bin/rails test test/controllers/exchange_requests_controller_test.rb`
Expected: PASS (5 tests)

- [ ] **Step 7: Commit**

```bash
git add config/routes.rb app/controllers/exchange_requests_controller.rb \
        app/views/exchange_requests/index.html.erb app/views/exchange_requests/show.html.erb \
        test/controllers/exchange_requests_controller_test.rb
git commit -m "feat: add exchange requests admin review screen"
```

---

### Task 15: Sidebar navigation entry

**Files:**
- Modify: `app/views/layouts/partials/_sidebar.html.erb`

**Interfaces:**
- Consumes: `exchange_requests_path` (Task 14).
- Produces: nothing consumed by later tasks — this is the last integration point.

- [ ] **Step 1: Add the link**

In `app/views/layouts/partials/_sidebar.html.erb`, inside the "Operações" `<details>` block (the one containing the links to `orders_path`, `customers_path`, `products_path`), add after the `products_path` link:
```erb
          <%= link_to exchange_requests_path, class: "crm-sidebar__link crm-sidebar__link--sub #{'active' if request.path.start_with?(exchange_requests_path) || request.path.start_with?('/crm/exchange_config')}" do %>
            <i class="fa-solid fa-rotate crm-fa"></i>
            Trocas e Devoluções
          <% end %>
```

And update the `operacoes_active` line just above the `<details>` block to also open the submenu when on an exchange page:
```erb
      <% operacoes_active = request.path.start_with?(orders_path) || request.path.start_with?(customers_path) ||
                             request.path.start_with?(products_path) || request.path.start_with?(exchange_requests_path) ||
                             request.path.start_with?('/crm/exchange_config') %>
```

- [ ] **Step 2: Manually verify**

Run: `bin/rails server` (or reuse a running dev server), sign in as a client user, confirm "Trocas e Devoluções" appears under "Operações" and links to `exchange_requests_path`.
Expected: link visible, navigates to the (empty) index page without error.

- [ ] **Step 3: Commit**

```bash
git add app/views/layouts/partials/_sidebar.html.erb
git commit -m "feat: add Trocas e Devoluções to the sidebar"
```

---

### Task 16: SCSS

**Files:**
- Modify: `app/assets/stylesheets/admin.scss`
- Create: `app/assets/stylesheets/pages/exchanges.scss`

**Interfaces:**
- Consumes: class names used in Tasks 12, 13, 14 views (`exchange-wizard*`).
- Produces: nothing consumed by other tasks.

- [ ] **Step 1: Register the new stylesheet**

In `app/assets/stylesheets/admin.scss`, add a line after `*= require pages/email_configurations`:
```
 *= require pages/exchanges
```

- [ ] **Step 2: Write the stylesheet**

`app/assets/stylesheets/pages/exchanges.scss`:
```scss
.exchange-wizard {
  min-height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 2rem 1rem;
  background: #f7f7f9;
}

.exchange-wizard__card {
  background: #fff;
  border-radius: 12px;
  box-shadow: 0 4px 24px rgba(0, 0, 0, 0.08);
  padding: 2rem;
  max-width: 560px;
  width: 100%;
}

.exchange-wizard__logo {
  max-height: 56px;
  margin-bottom: 1rem;
}

.exchange-wizard__title {
  margin: 0 0 0.5rem;
  font-size: 1.25rem;
}

.exchange-wizard__instructions {
  color: #555;
  font-size: 0.9rem;
}

.exchange-wizard__field {
  margin-bottom: 1rem;

  label {
    display: block;
    margin-bottom: 0.25rem;
    font-weight: 600;
    font-size: 0.85rem;
  }

  input {
    width: 100%;
    padding: 0.6rem 0.75rem;
    border: 1px solid #ddd;
    border-radius: 8px;
  }
}

.exchange-wizard__item {
  border: 1px solid #eee;
  border-radius: 8px;
  padding: 0.75rem;
  margin-bottom: 0.75rem;
}

.exchange-wizard__notice {
  background: #fff7e6;
  border: 1px solid #ffe1a8;
  border-radius: 8px;
  padding: 0.75rem 1rem;
  font-size: 0.85rem;
}

.exchange-wizard__submit {
  border: none;
  color: #fff;
  padding: 0.75rem 1.25rem;
  border-radius: 8px;
  font-weight: 600;
  cursor: pointer;
  width: 100%;
}
```

- [ ] **Step 3: Verify assets compile**

Run: `bin/rails assets:precompile RAILS_ENV=test` (or start the dev server and load `edit_exchange_config_path` / `new_exchange_path` to confirm no Sprockets error)
Expected: no errors; `admin.css` includes the new rules.

- [ ] **Step 4: Commit**

```bash
git add app/assets/stylesheets/admin.scss app/assets/stylesheets/pages/exchanges.scss
git commit -m "feat: style the public exchange wizard"
```

---

## Self-Review Notes

- **Spec coverage:** data model (Tasks 1–4), live order lookup (Task 5), eligibility rule (Task 6), rate limiting (Task 7), public 3-step wizard (Task 12), admin config screen (Task 13), admin review/approve/reject/complete screen (Task 14), sidebar entry (Task 15), 4 configurable e-mails + placeholders (Tasks 2, 10), coupon on approval as a fixed amount with configurable validity (Tasks 8, 11) are all covered. Styling (Task 16) covers the public page only, matching the spec's focus.
- **Placeholder scan:** no TBD/TODO; every step has real code or an exact command.
- **Type consistency:** `Shopify::FindOrderForExchange` / order Hash shape (`:id, :number, :email, :cancelled, :fulfilled_at, :items`) is identical across Tasks 5, 6, 12. `Exchange::EligibilityCalculator` return symbols (`:cancelled, :not_fulfilled, :return_and_exchange, :exchange_only`) match between Tasks 6 and 12. `SendExchangeEmailJob` `kind` strings (`'requested', 'approved', 'rejected', 'completed'`) match across Tasks 10, 11, 12, 14. `ExchangeRequestItem#kind` enum values (`troca`, `devolucao`) match across Tasks 3, 4, 12.
- Task 3's test file depends on `ExchangeRequest`, which doesn't exist until Task 4 — flagged explicitly in Task 3 Step 4 so the executor isn't confused by a still-red test at that point; Task 4 Step 4 re-runs both files together as the real gate.
