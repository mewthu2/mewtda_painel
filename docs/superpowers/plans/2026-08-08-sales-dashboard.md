# Dashboard de Vendas (ROAS/CAC mensal) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a per-client, month-based sales dashboard (`/painel/vendas`) showing Ticket
Médio, Faturamento, Taxa de Conversão, ROAS faturado e CAC, fed by Shopify orders plus
Google Ads (OAuth) and Meta Ads (pasted token) spend, gated by an admin-only toggle on the
client record.

**Architecture:** Rails 7.2 monolith. New columns on `orders`/`clients`, a new
`ad_cost_snapshots` table, a `Sales::MonthlyMetrics` PORO that does all calculation, two
cost-fetcher services (`Meta::MonthlyCostFetcher`, `GoogleAds::MonthlyCostFetcher`) invoked
on demand by `AdCostSyncJob`, a `GoogleAdsController` for the one-time-per-client OAuth
handshake, and a `SalesDashboardController` + view that ties it together.

**Tech Stack:** Ruby 3.2 / Rails 7.2, PostgreSQL, HTTParty (already in Gemfile) for all
outbound HTTP, Active Record Encryption for the two new secret columns, Minitest +
fixtures (no RSpec/Mocha/WebMock in this repo — HTTP calls are stubbed with
`Object#stub`/`Minitest::Mock`).

## Global Constraints

- Faturamento = `Σ total_price` (líquido de desconto, inclui frete/imposto) sobre pedidos
  não cancelados do mês. Vendas brutas = `Σ subtotal_price`; Descontos = `Σ total_discounts`.
- A tag de filtro (ex.: `VendedoraElo`) é **opcional**, nunca o padrão — o dashboard mostra
  o total da loja por padrão.
- Taxa de conversão usa sessões únicas do `ShopifyEvent` (`kind: "page_viewed"`), não GA4.
- GA4 está fora de escopo como fonte de custo.
- CAC usa apenas clientes novos (primeiro pedido não-cancelado no mês), não o total de pedidos.
- Sync de custo de anúncio é sob demanda (botão), não agendado.
- Meta Ads: token de longa duração colado pelo admin, sem OAuth no app.
- Google Ads: único caminho é OAuth por cliente (a API não aceita chave); precisa de
  `GOOGLE_ADS_CLIENT_ID`, `GOOGLE_ADS_CLIENT_SECRET`, `GOOGLE_ADS_DEVELOPER_TOKEN` como env
  vars — o Developer Token é um cadastro/aprovação fora do código, de responsabilidade do
  time da Mewtda.
- Dashboard acessível em `sales_dashboard_enabled? == true`; admins sempre podem acessar
  independente do toggle.

Spec de referência: `docs/superpowers/specs/2026-08-08-sales-dashboard-design.md`.

---

## File Structure

```
db/migrate/20260808120001_add_sales_dashboard_enabled_to_clients.rb   (new)
db/migrate/20260808120002_add_revenue_fields_to_orders.rb             (new)
db/migrate/20260808120003_add_ad_integration_fields_to_clients.rb     (new)
db/migrate/20260808120004_create_ad_cost_snapshots.rb                 (new)

config/application.rb                                                 (modify — AR Encryption config)
.env                                                                   (modify — new local dev keys, gitignored)

app/models/client.rb                                                  (modify — encrypts, helper methods)
app/models/order.rb                                                   (modify — cancelled scope)
app/models/ad_cost_snapshot.rb                                        (new)

app/models/shopify/orders.rb                                          (modify — sync new fields)
app/jobs/orders_update_job.rb                                         (modify — sync_single_order fields)

app/services/sales/monthly_metrics.rb                                 (new)
app/services/meta/monthly_cost_fetcher.rb                             (new)
app/services/google_ads/monthly_cost_fetcher.rb                       (new)
app/jobs/ad_cost_sync_job.rb                                          (new)

app/controllers/google_ads_controller.rb                              (new)
app/controllers/concerns/client_scoped.rb                             (new)
app/controllers/dashboard_controller.rb                               (modify — use ClientScoped)
app/controllers/sales_dashboard_controller.rb                         (new)
app/controllers/clients_controller.rb                                 (modify — permit new params)

app/views/clients/_form.html.erb                                      (modify — new sections)
app/views/sales_dashboard/index.html.erb                              (new)
app/views/layouts/partials/_header.html.erb                           (modify — nav link)

config/routes.rb                                                      (modify)

test/test_helper.rb                                                                    (modify — Devise test helpers)
test/models/client_test.rb                                                             (modify)
test/models/order_test.rb                                                              (new)
test/models/ad_cost_snapshot_test.rb                                                    (new)
test/models/shopify/orders_test.rb                                                      (new)
test/services/sales/monthly_metrics_test.rb                                             (new)
test/services/meta/monthly_cost_fetcher_test.rb                                         (new)
test/services/google_ads/monthly_cost_fetcher_test.rb                                   (new)
test/jobs/ad_cost_sync_job_test.rb                                                       (new)
test/controllers/google_ads_controller_test.rb                                          (new)
test/controllers/clients_controller_test.rb                                             (new)
test/controllers/sales_dashboard_controller_test.rb                                     (new)
```

---

### Task 1: Schema foundation — sales dashboard flag & order revenue fields

**Files:**
- Create: `db/migrate/20260808120001_add_sales_dashboard_enabled_to_clients.rb`
- Create: `db/migrate/20260808120002_add_revenue_fields_to_orders.rb`
- Modify: `app/models/order.rb`
- Test: `test/models/order_test.rb`

**Interfaces:**
- Produces: `Client#sales_dashboard_enabled` (boolean, default false), `Order#subtotal_price`,
  `Order#total_discounts`, `Order#total_price` (decimal), `Order#cancelled_at` (datetime),
  `Order.not_cancelled` scope.

- [ ] **Step 1: Write the failing test**

```ruby
# test/models/order_test.rb
require 'test_helper'

class OrderTest < ActiveSupport::TestCase
  def build_client
    Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
  end

  test 'stores subtotal_price, total_discounts, total_price and cancelled_at' do
    client = build_client

    order = Order.create!(
      client: client,
      shopify_order_id: '1001',
      subtotal_price: 100.0,
      total_discounts: 10.0,
      total_price: 90.0,
      cancelled_at: nil
    )

    assert_equal 100.0, order.subtotal_price.to_f
    assert_equal 10.0, order.total_discounts.to_f
    assert_equal 90.0, order.total_price.to_f
    assert_nil order.cancelled_at
  end

  test 'not_cancelled scope excludes orders with cancelled_at set' do
    client = build_client

    active = Order.create!(client: client, shopify_order_id: '2001', cancelled_at: nil)
    cancelled = Order.create!(client: client, shopify_order_id: '2002', cancelled_at: Time.current)

    result = Order.not_cancelled

    assert_includes result, active
    assert_not_includes result, cancelled
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/models/order_test.rb`
Expected: FAIL — `subtotal_price` etc. are unknown attributes, `not_cancelled` is an
undefined method.

- [ ] **Step 3: Add the migrations**

```ruby
# db/migrate/20260808120001_add_sales_dashboard_enabled_to_clients.rb
class AddSalesDashboardEnabledToClients < ActiveRecord::Migration[7.2]
  def change
    add_column :clients, :sales_dashboard_enabled, :boolean, default: false, null: false
  end
end
```

```ruby
# db/migrate/20260808120002_add_revenue_fields_to_orders.rb
class AddRevenueFieldsToOrders < ActiveRecord::Migration[7.2]
  def change
    add_column :orders, :subtotal_price, :decimal, precision: 12, scale: 2
    add_column :orders, :total_discounts, :decimal, precision: 12, scale: 2
    add_column :orders, :total_price, :decimal, precision: 12, scale: 2
    add_column :orders, :cancelled_at, :datetime

    add_index :orders, :cancelled_at
  end
end
```

Run: `bin/rails db:migrate`

- [ ] **Step 4: Add the `not_cancelled` scope**

```ruby
# app/models/order.rb
class Order < ApplicationRecord
  belongs_to :customer, optional: true
  belongs_to :client
  belongs_to :location, optional: true
  has_many :order_items, dependent: :destroy
  has_many :campaign_actions, dependent: :nullify

  # Escopos de busca
  scope :by_number, lambda { |q| where('shopify_order_number ILIKE ?', "%#{q}%") if q.present? }
  scope :by_kinds,  lambda { |k| where(kinds: k) if k.present? }
  scope :by_staff,  lambda { |s| where('staff_name ILIKE ?', "%#{s}%") if s.present? }
  scope :by_date_from, lambda { |d| where('shopify_creation_date >= ?', d.to_date.beginning_of_day) if d.present? }
  scope :by_date_to,   lambda { |d| where('shopify_creation_date <= ?', d.to_date.end_of_day) if d.present? }
  scope :not_cancelled, -> { where(cancelled_at: nil) }

  # ... (rest of the file unchanged)
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bin/rails test test/models/order_test.rb`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add db/migrate/20260808120001_add_sales_dashboard_enabled_to_clients.rb \
        db/migrate/20260808120002_add_revenue_fields_to_orders.rb \
        db/schema.rb app/models/order.rb test/models/order_test.rb
git commit -m "feat: add sales dashboard flag and order revenue fields"
```

---

### Task 2: Ad integration credential fields on clients (Active Record Encryption)

This is the first use of Active Record Encryption in this codebase — the app currently
stores all third-party secrets (`shopify_access_token`, `zapi_*`) as plain-text columns and
manages all secrets via `ENV`/`.env`/Heroku config vars, never Rails credentials. To stay
consistent with that pattern, the encryption keys are read from `ENV` in
`config/application.rb` rather than `config/credentials.yml.enc`.

**Files:**
- Create: `db/migrate/20260808120003_add_ad_integration_fields_to_clients.rb`
- Modify: `config/application.rb`
- Modify: `.env` (local only — add generated dev keys, already gitignored)
- Modify: `app/models/client.rb`
- Test: `test/models/client_test.rb`

**Interfaces:**
- Produces: `Client#meta_access_token` (encrypted), `Client#meta_ad_account_id`,
  `Client#google_ads_customer_id`, `Client#google_ads_refresh_token` (encrypted),
  `Client#google_ads_connected_at`, `Client#meta_configured?`, `Client#google_ads_configured?`.

- [ ] **Step 1: Generate local encryption keys**

Run in a console (do this once, values are random and local to your machine):

```bash
bin/rails runner 'puts "AR_ENCRYPTION_PRIMARY_KEY=#{SecureRandom.alphanumeric(32)}"; puts "AR_ENCRYPTION_DETERMINISTIC_KEY=#{SecureRandom.alphanumeric(32)}"; puts "AR_ENCRYPTION_KEY_DERIVATION_SALT=#{SecureRandom.alphanumeric(32)}"'
```

Append the three printed lines to `.env` (already gitignored — confirm with
`git check-ignore .env`). **Production needs the same three vars set as Heroku config
vars** (`heroku config:set AR_ENCRYPTION_PRIMARY_KEY=... AR_ENCRYPTION_DETERMINISTIC_KEY=... AR_ENCRYPTION_KEY_DERIVATION_SALT=...`)
before this deploys — different values than dev/test, generated the same way.

- [ ] **Step 2: Configure Active Record Encryption**

```ruby
# config/application.rb
module MewtdaPainel
  class Application < Rails::Application
    config.load_defaults 7.0

    config.time_zone = 'Brasilia'

    config.active_record.default_timezone = :utc

    config.i18n.default_locale = :'pt-BR'
    config.i18n.available_locales = [:'pt-BR', :en]

    config.active_record.encryption.primary_key = ENV['AR_ENCRYPTION_PRIMARY_KEY']
    config.active_record.encryption.deterministic_key = ENV['AR_ENCRYPTION_DETERMINISTIC_KEY']
    config.active_record.encryption.key_derivation_salt = ENV['AR_ENCRYPTION_KEY_DERIVATION_SALT']
  end
end
```

- [ ] **Step 3: Write the failing test**

```ruby
# test/models/client_test.rb
require 'test_helper'

class ClientTest < ActiveSupport::TestCase
  test 'encrypts meta_access_token and google_ads_refresh_token at rest' do
    client = Client.create!(
      name: 'Loja Teste',
      email: "loja-#{SecureRandom.hex(4)}@example.com",
      meta_access_token: 'EAABsecrettoken',
      meta_ad_account_id: 'act_123',
      google_ads_customer_id: '1234567890',
      google_ads_refresh_token: '1//refreshtoken'
    )

    assert_equal 'EAABsecrettoken', client.reload.meta_access_token
    assert_equal '1//refreshtoken', client.reload.google_ads_refresh_token

    raw_value = Client.connection.select_value(
      "SELECT meta_access_token FROM clients WHERE id = #{client.id}"
    )
    assert_not_equal 'EAABsecrettoken', raw_value
  end

  test 'meta_configured? and google_ads_configured? reflect presence of credentials' do
    client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
    assert_not client.meta_configured?
    assert_not client.google_ads_configured?

    client.update!(meta_access_token: 'token', meta_ad_account_id: 'act_1')
    assert client.reload.meta_configured?

    client.update!(google_ads_refresh_token: 'refresh', google_ads_customer_id: '123')
    assert client.reload.google_ads_configured?
  end
end
```

- [ ] **Step 4: Run test to verify it fails**

Run: `bin/rails test test/models/client_test.rb`
Expected: FAIL — unknown attribute `meta_access_token` for Client.

- [ ] **Step 5: Add the migration**

```ruby
# db/migrate/20260808120003_add_ad_integration_fields_to_clients.rb
class AddAdIntegrationFieldsToClients < ActiveRecord::Migration[7.2]
  def change
    add_column :clients, :meta_access_token, :string
    add_column :clients, :meta_ad_account_id, :string
    add_column :clients, :google_ads_customer_id, :string
    add_column :clients, :google_ads_refresh_token, :string
    add_column :clients, :google_ads_connected_at, :datetime
  end
end
```

Run: `bin/rails db:migrate`

- [ ] **Step 6: Update the model**

```ruby
# app/models/client.rb
class Client < ApplicationRecord
  has_many :users, dependent: :nullify
  has_many :campaigns, dependent: :destroy

  encrypts :meta_access_token, :google_ads_refresh_token

  validates :name, presence: true
  validates :email, presence: true

  def zapi_configured?
    zapi_instance_id.present? &&
      zapi_instance_token.present? &&
      zapi_client_token.present?
  end

  def shopify_configured?
    shopify_shop_url.present? && shopify_access_token.present?
  end

  def meta_configured?
    meta_access_token.present? && meta_ad_account_id.present?
  end

  def google_ads_configured?
    google_ads_refresh_token.present? && google_ads_customer_id.present?
  end
end
```

- [ ] **Step 7: Run test to verify it passes**

Run: `bin/rails test test/models/client_test.rb`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add db/migrate/20260808120003_add_ad_integration_fields_to_clients.rb \
        db/schema.rb config/application.rb app/models/client.rb test/models/client_test.rb
git commit -m "feat: add encrypted Meta/Google Ads credential fields to clients"
```

Do **not** commit `.env` — verify it stays untracked with `git status`.

---

### Task 3: `ad_cost_snapshots` table and model

**Files:**
- Create: `db/migrate/20260808120004_create_ad_cost_snapshots.rb`
- Create: `app/models/ad_cost_snapshot.rb`
- Test: `test/models/ad_cost_snapshot_test.rb`

**Interfaces:**
- Consumes: `Client` (from Task 1/2).
- Produces: `AdCostSnapshot` with columns `client_id, platform, year, month, cost, fetched_at`,
  `AdCostSnapshot::PLATFORMS = %w[google_ads meta]`.

- [ ] **Step 1: Write the failing test**

```ruby
# test/models/ad_cost_snapshot_test.rb
require 'test_helper'

class AdCostSnapshotTest < ActiveSupport::TestCase
  def build_client
    Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
  end

  test 'valid with a known platform, year, month and non-negative cost' do
    snapshot = AdCostSnapshot.new(
      client: build_client, platform: 'meta', year: 2026, month: 3, cost: 150.0, fetched_at: Time.current
    )
    assert snapshot.valid?
  end

  test 'invalid with an unknown platform' do
    snapshot = AdCostSnapshot.new(
      client: build_client, platform: 'tiktok', year: 2026, month: 3, cost: 150.0
    )
    assert_not snapshot.valid?
    assert_includes snapshot.errors[:platform], 'is not included in the list'
  end

  test 'invalid with a negative cost' do
    snapshot = AdCostSnapshot.new(
      client: build_client, platform: 'meta', year: 2026, month: 3, cost: -1
    )
    assert_not snapshot.valid?
  end

  test 'unique per client, platform, year and month' do
    client = build_client
    AdCostSnapshot.create!(client: client, platform: 'meta', year: 2026, month: 3, cost: 100)

    duplicate = AdCostSnapshot.new(client: client, platform: 'meta', year: 2026, month: 3, cost: 200)

    assert_not duplicate.valid?
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/models/ad_cost_snapshot_test.rb`
Expected: FAIL — `uninitialized constant AdCostSnapshot`.

- [ ] **Step 3: Add the migration**

```ruby
# db/migrate/20260808120004_create_ad_cost_snapshots.rb
class CreateAdCostSnapshots < ActiveRecord::Migration[7.2]
  def change
    create_table :ad_cost_snapshots do |t|
      t.references :client, null: false, foreign_key: true
      t.string :platform, null: false
      t.integer :year, null: false
      t.integer :month, null: false
      t.decimal :cost, precision: 12, scale: 2, null: false, default: 0
      t.datetime :fetched_at

      t.timestamps
    end

    add_index :ad_cost_snapshots, [:client_id, :platform, :year, :month],
              unique: true, name: 'index_ad_cost_snapshots_on_client_platform_month'
  end
end
```

Run: `bin/rails db:migrate`

- [ ] **Step 4: Add the model**

```ruby
# app/models/ad_cost_snapshot.rb
class AdCostSnapshot < ApplicationRecord
  belongs_to :client

  PLATFORMS = %w[google_ads meta].freeze

  validates :platform, inclusion: { in: PLATFORMS }
  validates :year, presence: true
  validates :month, presence: true, inclusion: { in: 1..12 }
  validates :cost, numericality: { greater_than_or_equal_to: 0 }
  validates :platform, uniqueness: { scope: %i[client_id year month] }
end
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bin/rails test test/models/ad_cost_snapshot_test.rb`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add db/migrate/20260808120004_create_ad_cost_snapshots.rb db/schema.rb \
        app/models/ad_cost_snapshot.rb test/models/ad_cost_snapshot_test.rb
git commit -m "feat: add ad_cost_snapshots table and model"
```

---

### Task 4: Persist tags/subtotal/discount/total/cancelled_at on Shopify order sync

**Files:**
- Modify: `app/models/shopify/orders.rb`
- Modify: `app/jobs/orders_update_job.rb`
- Test: `test/models/shopify/orders_test.rb`

**Interfaces:**
- Consumes: `Order` (Task 1).
- Produces: no new public interface — `Shopify::Orders.create_or_update_order_from_shopify`
  now also assigns `tags`, `subtotal_price`, `total_discounts`, `total_price`, `cancelled_at`.

- [ ] **Step 1: Write the failing test**

```ruby
# test/models/shopify/orders_test.rb
require 'test_helper'

class Shopify::OrdersTest < ActiveSupport::TestCase
  def build_client
    Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
  end

  def shopify_order_payload(overrides = {})
    {
      'id' => 555_001,
      'name' => '#1001',
      'created_at' => '2026-03-10T12:00:00-03:00',
      'tags' => 'VendedoraElo, promo',
      'subtotal_price' => '200.00',
      'total_discounts' => '20.00',
      'total_price' => '180.00',
      'cancelled_at' => nil,
      'note_attributes' => [],
      'line_items' => [],
      'customer' => nil
    }.merge(overrides)
  end

  test 'persists tags, subtotal_price, total_discounts, total_price and cancelled_at' do
    client = build_client

    order = Shopify::Orders.create_or_update_order_from_shopify(
      shopify_order_payload,
      session: nil,
      client: client
    )

    order.reload
    assert_equal 'VendedoraElo, promo', order.tags
    assert_equal 200.00, order.subtotal_price.to_f
    assert_equal 20.00, order.total_discounts.to_f
    assert_equal 180.00, order.total_price.to_f
    assert_nil order.cancelled_at
  end

  test 'persists cancelled_at when the Shopify order was cancelled' do
    client = build_client

    order = Shopify::Orders.create_or_update_order_from_shopify(
      shopify_order_payload('id' => 555_002, 'cancelled_at' => '2026-03-11T09:00:00-03:00'),
      session: nil,
      client: client
    )

    assert order.reload.cancelled_at.present?
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/models/shopify/orders_test.rb`
Expected: FAIL — `order.tags`/`order.subtotal_price` etc. come back `nil` because the sync
never assigns them (`find_or_create_customer_from_shopify` will also be called with
`session: nil`; since `shopify_order['customer']` is `nil` in the payload, that method
returns early without hitting the network, so no stubbing is needed here).

- [ ] **Step 3: Update `Shopify::Orders`**

```ruby
# app/models/shopify/orders.rb — inside sync_shopify_orders_to_rails
      query_params = {
        limit: limit,
        status: status,
        fields: 'id,name,created_at,line_items,note_attributes,customer,tags,subtotal_price,total_discounts,total_price,cancelled_at'
      }
```

```ruby
# app/models/shopify/orders.rb — inside create_or_update_order_from_shopify
      order.assign_attributes(
        shopify_order_number: shopify_order_number,
        staff_id: staff_id.presence || order.staff_id,
        staff_name: staff_name.presence || order.staff_name,
        location_id: location.id,
        shopify_creation_date: shopify_created_at,
        customer_id: customer&.id,
        client_id: client.id,
        tags: shopify_order['tags'],
        subtotal_price: shopify_order['subtotal_price'],
        total_discounts: shopify_order['total_discounts'],
        total_price: shopify_order['total_price'],
        cancelled_at: shopify_order['cancelled_at'].presence && Time.parse(shopify_order['cancelled_at'])
      )
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/models/shopify/orders_test.rb`
Expected: PASS

- [ ] **Step 5: Update `OrdersUpdateJob#sync_single_order` to request the same fields**

```ruby
# app/jobs/orders_update_job.rb — inside sync_single_order
    response = client_api.get(
      path: "orders/#{shopify_order_id}.json",
      query: {
        fields: 'id,created_at,line_items,note_attributes,customer,tags,subtotal_price,total_discounts,total_price,cancelled_at'
      }
    )
```

- [ ] **Step 6: Run the full test suite to make sure nothing else broke**

Run: `bin/rails test`
Expected: PASS (all green, including the two new test files from earlier tasks)

- [ ] **Step 7: Commit**

```bash
git add app/models/shopify/orders.rb app/jobs/orders_update_job.rb test/models/shopify/orders_test.rb
git commit -m "feat: sync order tags, discounts, totals and cancellation from Shopify"
```

---

### Task 5: `Sales::MonthlyMetrics` calculation service

**Files:**
- Create: `app/services/sales/monthly_metrics.rb`
- Test: `test/services/sales/monthly_metrics_test.rb`

**Interfaces:**
- Consumes: `Order.not_cancelled` (Task 1), `Client#meta_configured?`/`#google_ads_configured?`
  (Task 2), `AdCostSnapshot` (Task 3), `ShopifyEvent` (existing model).
- Produces: `Sales::MonthlyMetrics.new(client:, year:, month:, tag: nil).call` → Hash with keys
  `:revenue, :gross_sales, :discounts, :orders_count, :avg_ticket, :conversion_rate, :ad_cost,
  :ad_cost_available, :configured_platforms, :roas, :new_customers_count, :cac`.

- [ ] **Step 1: Write the failing tests**

```ruby
# test/services/sales/monthly_metrics_test.rb
require 'test_helper'

class Sales::MonthlyMetricsTest < ActiveSupport::TestCase
  def setup
    @client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
    @integration_user = IntegrationUser.create!(
      name: 'Pixel', slug: "pixel-#{SecureRandom.hex(4)}", api_secret: SecureRandom.hex(8), client: @client
    )
  end

  def create_order(attrs = {})
    Order.create!({
      client: @client,
      shopify_order_id: SecureRandom.hex(6),
      shopify_creation_date: Time.zone.local(2026, 3, 15),
      subtotal_price: 100,
      total_discounts: 0,
      total_price: 100,
      cancelled_at: nil,
      tags: nil
    }.merge(attrs))
  end

  def create_page_view(session_id, at: Time.zone.local(2026, 3, 15))
    ShopifyEvent.create!(
      client: @client, integration_user: @integration_user, kind: 'page_viewed',
      session_id: session_id, created_at: at
    )
  end

  def call(tag: nil)
    Sales::MonthlyMetrics.new(client: @client, year: 2026, month: 3, tag: tag).call
  end

  test 'revenue, gross_sales and discounts sum total_price/subtotal_price/total_discounts of the month' do
    create_order(total_price: 100, subtotal_price: 120, total_discounts: 20)
    create_order(total_price: 50, subtotal_price: 50, total_discounts: 0)
    create_order(shopify_creation_date: Time.zone.local(2026, 2, 15), total_price: 999) # outside the month

    result = call

    assert_equal 150.0, result[:revenue].to_f
    assert_equal 170.0, result[:gross_sales].to_f
    assert_equal 20.0, result[:discounts].to_f
    assert_equal 2, result[:orders_count]
  end

  test 'excludes cancelled orders' do
    create_order(total_price: 100)
    create_order(total_price: 500, cancelled_at: Time.current)

    result = call

    assert_equal 100.0, result[:revenue].to_f
    assert_equal 1, result[:orders_count]
  end

  test 'avg_ticket is revenue divided by orders_count, nil when there are no orders' do
    create_order(total_price: 100)
    create_order(total_price: 300)

    assert_equal 200.0, call[:avg_ticket].to_f

    empty_client = Client.create!(name: 'Vazia', email: "vazia-#{SecureRandom.hex(4)}@example.com")
    result = Sales::MonthlyMetrics.new(client: empty_client, year: 2026, month: 3).call
    assert_nil result[:avg_ticket]
  end

  test 'tag filter restricts the order scope without affecting session count' do
    create_order(total_price: 100, tags: 'VendedoraElo, promo')
    create_order(total_price: 300, tags: 'outra-tag')
    create_page_view('s1')
    create_page_view('s2')

    result = call(tag: 'VendedoraElo')

    assert_equal 100.0, result[:revenue].to_f
    assert_equal 1, result[:orders_count]
    assert_equal 50.0, result[:conversion_rate]
  end

  test 'conversion_rate is orders_count / unique sessions * 100, nil when there are no sessions' do
    create_order
    create_order
    create_page_view('s1')
    create_page_view('s1') # same session, counted once
    create_page_view('s2')
    create_page_view('s2')

    assert_equal 100.0, call[:conversion_rate]

    empty_client = Client.create!(name: 'Vazia', email: "vazia2-#{SecureRandom.hex(4)}@example.com")
    result = Sales::MonthlyMetrics.new(client: empty_client, year: 2026, month: 3).call
    assert_nil result[:conversion_rate]
  end

  test 'ad_cost_available is false and roas/cac are nil when a configured platform has no snapshot yet' do
    @client.update!(meta_access_token: 'token', meta_ad_account_id: 'act_1')
    create_order(total_price: 100)

    result = call

    assert_equal ['meta'], result[:configured_platforms]
    assert_not result[:ad_cost_available]
    assert_nil result[:roas]
    assert_nil result[:cac]
  end

  test 'roas is revenue / ad_cost and cac is ad_cost / new_customers_count when costs are synced' do
    @client.update!(meta_access_token: 'token', meta_ad_account_id: 'act_1')
    AdCostSnapshot.create!(client: @client, platform: 'meta', year: 2026, month: 3, cost: 100, fetched_at: Time.current)

    new_customer = Customer.create!(shopify_customer_id: SecureRandom.hex(6))
    create_order(total_price: 400, customer: new_customer)

    result = call

    assert result[:ad_cost_available]
    assert_equal 100.0, result[:ad_cost].to_f
    assert_equal 4.0, result[:roas].to_f
    assert_equal 1, result[:new_customers_count]
    assert_equal 100.0, result[:cac].to_f
  end

  test 'new_customers_count only counts customers whose earliest non-cancelled order falls in the month' do
    returning_customer = Customer.create!(shopify_customer_id: SecureRandom.hex(6))
    create_order(shopify_creation_date: Time.zone.local(2026, 1, 5), customer: returning_customer)
    create_order(shopify_creation_date: Time.zone.local(2026, 3, 10), customer: returning_customer)

    brand_new_customer = Customer.create!(shopify_customer_id: SecureRandom.hex(6))
    create_order(shopify_creation_date: Time.zone.local(2026, 3, 12), customer: brand_new_customer)

    assert_equal 1, call[:new_customers_count]
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/sales/monthly_metrics_test.rb`
Expected: FAIL — `uninitialized constant Sales::MonthlyMetrics`.

- [ ] **Step 3: Implement the service**

```ruby
# app/services/sales/monthly_metrics.rb
module Sales
  class MonthlyMetrics
    def initialize(client:, year:, month:, tag: nil)
      @client = client
      @year = year
      @month = month
      @tag = tag
    end

    def call
      {
        revenue: revenue,
        gross_sales: gross_sales,
        discounts: discounts,
        orders_count: orders_count,
        avg_ticket: avg_ticket,
        conversion_rate: conversion_rate,
        ad_cost: ad_cost,
        ad_cost_available: ad_cost_available?,
        configured_platforms: configured_platforms,
        roas: roas,
        new_customers_count: new_customers_count,
        cac: cac
      }
    end

    private

    attr_reader :client, :year, :month, :tag

    def period
      start = Time.zone.local(year, month, 1).beginning_of_day
      start..start.end_of_month
    end

    def orders_scope
      scope = Order.not_cancelled.where(client_id: client.id, shopify_creation_date: period)
      scope = scope.where('tags ILIKE ?', "%#{tag}%") if tag.present?
      scope
    end

    def revenue
      orders_scope.sum(:total_price)
    end

    def gross_sales
      orders_scope.sum(:subtotal_price)
    end

    def discounts
      orders_scope.sum(:total_discounts)
    end

    def orders_count
      orders_scope.count
    end

    def avg_ticket
      return nil if orders_count.zero?

      revenue / orders_count
    end

    def unique_sessions
      ShopifyEvent
        .where(client_id: client.id, kind: 'page_viewed', created_at: period)
        .distinct
        .count(:session_id)
    end

    def conversion_rate
      return nil if unique_sessions.zero?

      (orders_count.to_f / unique_sessions * 100).round(2)
    end

    def configured_platforms
      platforms = []
      platforms << 'google_ads' if client.google_ads_configured?
      platforms << 'meta' if client.meta_configured?
      platforms
    end

    def ad_cost_snapshots
      AdCostSnapshot.where(client_id: client.id, year: year, month: month)
    end

    def ad_cost_available?
      return false if configured_platforms.empty?

      configured_platforms.all? { |platform| ad_cost_snapshots.exists?(platform: platform) }
    end

    def ad_cost
      ad_cost_snapshots.sum(:cost)
    end

    def roas
      return nil unless ad_cost_available?
      return nil if ad_cost.zero?

      (revenue / ad_cost).round(2)
    end

    def new_customers_count
      Customer
        .joins(:orders)
        .where(orders: { client_id: client.id, cancelled_at: nil })
        .group('customers.id')
        .having('MIN(orders.shopify_creation_date) BETWEEN ? AND ?', period.first, period.last)
        .count
        .length
    end

    def cac
      return nil unless ad_cost_available?
      return nil if new_customers_count.zero?

      (ad_cost / new_customers_count).round(2)
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/services/sales/monthly_metrics_test.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/sales/monthly_metrics.rb test/services/sales/monthly_metrics_test.rb
git commit -m "feat: add Sales::MonthlyMetrics calculation service"
```

---

### Task 6: `Meta::MonthlyCostFetcher`

**Files:**
- Create: `app/services/meta/monthly_cost_fetcher.rb`
- Test: `test/services/meta/monthly_cost_fetcher_test.rb`

**Interfaces:**
- Consumes: `Client#meta_access_token`, `Client#meta_ad_account_id` (Task 2).
- Produces: `Meta::MonthlyCostFetcher.new(client:, year:, month:).call` → Float (spend in
  the month). Raises `Meta::MonthlyCostFetcher::FetchError` on failure.

- [ ] **Step 1: Write the failing tests**

```ruby
# test/services/meta/monthly_cost_fetcher_test.rb
require 'test_helper'

class Meta::MonthlyCostFetcherTest < ActiveSupport::TestCase
  FakeResponse = Struct.new(:success?, :parsed_response)

  def build_client
    Client.create!(
      name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com",
      meta_access_token: 'token123', meta_ad_account_id: 'act_1'
    )
  end

  test 'sums spend across all rows returned by the Graph API' do
    client = build_client
    response = FakeResponse.new(true, { 'data' => [{ 'spend' => '120.50' }, { 'spend' => '30.25' }] })

    HTTParty.stub :get, response do
      cost = Meta::MonthlyCostFetcher.new(client: client, year: 2026, month: 3).call
      assert_equal 150.75, cost
    end
  end

  test 'returns 0 when the Graph API returns no rows for the period' do
    client = build_client
    response = FakeResponse.new(true, { 'data' => [] })

    HTTParty.stub :get, response do
      cost = Meta::MonthlyCostFetcher.new(client: client, year: 2026, month: 3).call
      assert_equal 0, cost
    end
  end

  test 'raises FetchError with the API message when the call fails' do
    client = build_client
    response = FakeResponse.new(false, { 'error' => { 'message' => 'Invalid OAuth access token' } })

    HTTParty.stub :get, response do
      error = assert_raises(Meta::MonthlyCostFetcher::FetchError) do
        Meta::MonthlyCostFetcher.new(client: client, year: 2026, month: 3).call
      end
      assert_equal 'Invalid OAuth access token', error.message
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/meta/monthly_cost_fetcher_test.rb`
Expected: FAIL — `uninitialized constant Meta::MonthlyCostFetcher`.

- [ ] **Step 3: Implement the service**

```ruby
# app/services/meta/monthly_cost_fetcher.rb
module Meta
  class MonthlyCostFetcher
    class FetchError < StandardError; end

    GRAPH_API_VERSION = 'v20.0'.freeze

    def initialize(client:, year:, month:)
      @client = client
      @year = year
      @month = month
    end

    def call
      since = Time.zone.local(@year, @month, 1).to_date
      until_date = since.end_of_month

      response = HTTParty.get(
        "https://graph.facebook.com/#{GRAPH_API_VERSION}/#{@client.meta_ad_account_id}/insights",
        query: {
          fields: 'spend',
          time_range: { since: since.iso8601, until: until_date.iso8601 }.to_json,
          access_token: @client.meta_access_token
        }
      )

      unless response.success?
        message = response.parsed_response.dig('error', 'message') || 'Erro ao buscar custo do Meta Ads'
        raise FetchError, message
      end

      Array(response.parsed_response['data']).sum { |row| row['spend'].to_f }.round(2)
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/services/meta/monthly_cost_fetcher_test.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/meta/monthly_cost_fetcher.rb test/services/meta/monthly_cost_fetcher_test.rb
git commit -m "feat: add Meta::MonthlyCostFetcher"
```

---

### Task 7: `GoogleAds::MonthlyCostFetcher`

**Files:**
- Create: `app/services/google_ads/monthly_cost_fetcher.rb`
- Test: `test/services/google_ads/monthly_cost_fetcher_test.rb`

**Interfaces:**
- Consumes: `Client#google_ads_refresh_token`, `Client#google_ads_customer_id` (Task 2),
  `ENV['GOOGLE_ADS_CLIENT_ID']`, `ENV['GOOGLE_ADS_CLIENT_SECRET']`,
  `ENV['GOOGLE_ADS_DEVELOPER_TOKEN']`.
- Produces: `GoogleAds::MonthlyCostFetcher.new(client:, year:, month:).call` → Float (spend
  in the month, converted from micros). Raises `GoogleAds::MonthlyCostFetcher::FetchError`
  on failure.

- [ ] **Step 1: Write the failing tests**

```ruby
# test/services/google_ads/monthly_cost_fetcher_test.rb
require 'test_helper'

class GoogleAds::MonthlyCostFetcherTest < ActiveSupport::TestCase
  FakeResponse = Struct.new(:success?, :parsed_response)

  def build_client
    Client.create!(
      name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com",
      google_ads_refresh_token: 'refresh-token', google_ads_customer_id: '1234567890'
    )
  end

  test 'exchanges the refresh token and sums cost_micros across result chunks' do
    client = build_client

    responder = lambda do |_url, _options|
      if _url == 'https://oauth2.googleapis.com/token'
        FakeResponse.new(true, { 'access_token' => 'access-123' })
      else
        FakeResponse.new(true, [
          { 'results' => [{ 'metrics' => { 'costMicros' => '2000000' } }] },
          { 'results' => [{ 'metrics' => { 'costMicros' => '500000' } }] }
        ])
      end
    end

    HTTParty.stub :post, responder do
      cost = GoogleAds::MonthlyCostFetcher.new(client: client, year: 2026, month: 3).call
      assert_equal 2.5, cost
    end
  end

  test 'raises FetchError when the token exchange fails' do
    client = build_client
    response = FakeResponse.new(false, { 'error' => 'invalid_grant' })

    HTTParty.stub :post, response do
      assert_raises(GoogleAds::MonthlyCostFetcher::FetchError) do
        GoogleAds::MonthlyCostFetcher.new(client: client, year: 2026, month: 3).call
      end
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/google_ads/monthly_cost_fetcher_test.rb`
Expected: FAIL — `uninitialized constant GoogleAds::MonthlyCostFetcher`.

- [ ] **Step 3: Implement the service**

```ruby
# app/services/google_ads/monthly_cost_fetcher.rb
module GoogleAds
  class MonthlyCostFetcher
    class FetchError < StandardError; end

    API_VERSION = 'v17'.freeze
    TOKEN_URL = 'https://oauth2.googleapis.com/token'.freeze

    def initialize(client:, year:, month:)
      @client = client
      @year = year
      @month = month
    end

    def call
      access_token = fetch_access_token
      cost_micros = fetch_cost_micros(access_token)
      (cost_micros / 1_000_000.0).round(2)
    end

    private

    def fetch_access_token
      response = HTTParty.post(
        TOKEN_URL,
        body: {
          client_id: ENV['GOOGLE_ADS_CLIENT_ID'],
          client_secret: ENV['GOOGLE_ADS_CLIENT_SECRET'],
          refresh_token: @client.google_ads_refresh_token,
          grant_type: 'refresh_token'
        }
      )

      raise FetchError, 'Token do Google Ads expirado ou revogado' unless response.success?

      response.parsed_response['access_token']
    end

    def fetch_cost_micros(access_token)
      since = Time.zone.local(@year, @month, 1).to_date
      until_date = since.end_of_month
      customer_id = @client.google_ads_customer_id.to_s.delete('-')

      response = HTTParty.post(
        "https://googleads.googleapis.com/#{API_VERSION}/customers/#{customer_id}/googleAds:searchStream",
        headers: {
          'Authorization' => "Bearer #{access_token}",
          'developer-token' => ENV['GOOGLE_ADS_DEVELOPER_TOKEN'],
          'Content-Type' => 'application/json'
        },
        body: {
          query: "SELECT metrics.cost_micros FROM customer WHERE segments.date BETWEEN '#{since.iso8601}' AND '#{until_date.iso8601}'"
        }.to_json
      )

      raise FetchError, 'Erro ao buscar custo do Google Ads' unless response.success?

      Array(response.parsed_response).sum do |chunk|
        Array(chunk['results']).sum { |result| result.dig('metrics', 'costMicros').to_i }
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/services/google_ads/monthly_cost_fetcher_test.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/google_ads/monthly_cost_fetcher.rb test/services/google_ads/monthly_cost_fetcher_test.rb
git commit -m "feat: add GoogleAds::MonthlyCostFetcher"
```

---

### Task 8: `AdCostSyncJob`

**Files:**
- Create: `app/jobs/ad_cost_sync_job.rb`
- Test: `test/jobs/ad_cost_sync_job_test.rb`

**Interfaces:**
- Consumes: `GoogleAds::MonthlyCostFetcher`, `Meta::MonthlyCostFetcher` (Tasks 6/7),
  `AdCostSnapshot` (Task 3), `Client#google_ads_configured?`/`#meta_configured?` (Task 2).
- Produces: `AdCostSyncJob.new.perform(client_id:, year:, month:)` → Array of
  `AdCostSyncJob::Result` structs (`platform`, `status` (`:ok`/`:error`), `error_message`).

- [ ] **Step 1: Write the failing tests**

```ruby
# test/jobs/ad_cost_sync_job_test.rb
require 'test_helper'

class AdCostSyncJobTest < ActiveJob::TestCase
  class FakeFetcher
    def initialize(*); end
    def call = 123.45
  end

  class RaisingFetcher
    def initialize(*); end
    def call = raise GoogleAds::MonthlyCostFetcher::FetchError, 'Token expirado'
  end

  def build_client(**attrs)
    Client.create!({ name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com" }.merge(attrs))
  end

  test 'skips platforms without credentials configured' do
    client = build_client

    results = AdCostSyncJob.new.perform(client_id: client.id, year: 2026, month: 3)

    assert_empty results
  end

  test 'upserts an ad_cost_snapshot for each configured platform that succeeds' do
    client = build_client(meta_access_token: 'token', meta_ad_account_id: 'act_1')

    Meta::MonthlyCostFetcher.stub :new, ->(**) { FakeFetcher.new } do
      results = AdCostSyncJob.new.perform(client_id: client.id, year: 2026, month: 3)

      assert_equal 1, results.length
      assert_equal 'meta', results.first.platform
      assert_equal :ok, results.first.status
    end

    snapshot = AdCostSnapshot.find_by(client_id: client.id, platform: 'meta', year: 2026, month: 3)
    assert_equal 123.45, snapshot.cost.to_f
  end

  test 'records an error result without touching the snapshot when the fetcher raises' do
    client = build_client(google_ads_refresh_token: 'refresh', google_ads_customer_id: '123')

    GoogleAds::MonthlyCostFetcher.stub :new, ->(**) { RaisingFetcher.new } do
      results = AdCostSyncJob.new.perform(client_id: client.id, year: 2026, month: 3)

      assert_equal 1, results.length
      assert_equal 'google_ads', results.first.platform
      assert_equal :error, results.first.status
      assert_equal 'Token expirado', results.first.error_message
    end

    assert_nil AdCostSnapshot.find_by(client_id: client.id, platform: 'google_ads', year: 2026, month: 3)
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/jobs/ad_cost_sync_job_test.rb`
Expected: FAIL — `uninitialized constant AdCostSyncJob`.

- [ ] **Step 3: Implement the job**

```ruby
# app/jobs/ad_cost_sync_job.rb
class AdCostSyncJob < ApplicationJob
  queue_as :default

  Result = Struct.new(:platform, :status, :error_message)

  def perform(client_id:, year:, month:)
    client = Client.find(client_id)
    results = []

    if client.google_ads_configured?
      results << sync_platform(client: client, year: year, month: month, platform: 'google_ads') do
        GoogleAds::MonthlyCostFetcher.new(client: client, year: year, month: month).call
      end
    end

    if client.meta_configured?
      results << sync_platform(client: client, year: year, month: month, platform: 'meta') do
        Meta::MonthlyCostFetcher.new(client: client, year: year, month: month).call
      end
    end

    results
  end

  private

  def sync_platform(client:, year:, month:, platform:)
    cost = yield
    snapshot = AdCostSnapshot.find_or_initialize_by(client_id: client.id, platform: platform, year: year, month: month)
    snapshot.update!(cost: cost, fetched_at: Time.current)
    Result.new(platform, :ok, nil)
  rescue StandardError => e
    Rails.logger.error "[AdCostSyncJob] Falha ao sincronizar #{platform} para client #{client.id}: #{e.message}"
    Result.new(platform, :error, e.message)
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/jobs/ad_cost_sync_job_test.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/jobs/ad_cost_sync_job.rb test/jobs/ad_cost_sync_job_test.rb
git commit -m "feat: add AdCostSyncJob to upsert monthly ad cost snapshots"
```

---

### Task 9: Google Ads OAuth flow (`GoogleAdsController`)

**Files:**
- Create: `app/controllers/google_ads_controller.rb`
- Modify: `config/routes.rb`
- Modify: `test/test_helper.rb` (add Devise integration test helpers — needed here and by
  every controller test in the remaining tasks)
- Test: `test/controllers/google_ads_controller_test.rb`

**Interfaces:**
- Consumes: `Client#google_ads_refresh_token=`/`#google_ads_connected_at=` (Task 2),
  `ENV['GOOGLE_ADS_CLIENT_ID']`, `ENV['GOOGLE_ADS_CLIENT_SECRET']`.
- Produces: routes `client_google_ads_connect_path(client)` (GET),
  `google_ads_callback_url` (GET, fixed path — required by Google's OAuth redirect_uri
  matching), `client_google_ads_disconnect_path(client)` (DELETE).

- [ ] **Step 1: Add Devise integration test helpers**

```ruby
# test/test_helper.rb
ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
require 'rails/test_help'

class ActiveSupport::TestCase
  parallelize(workers: :number_of_processors)

  fixtures :all
end

class ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
end
```

- [ ] **Step 2: Write the failing tests**

```ruby
# test/controllers/google_ads_controller_test.rb
require 'test_helper'

class GoogleAdsControllerTest < ActionDispatch::IntegrationTest
  FakeResponse = Struct.new(:success?, :parsed_response)

  def build_admin
    User.create!(
      name: 'Admin', email: "admin-#{SecureRandom.hex(4)}@example.com",
      password: 'password123', password_confirmation: 'password123', profile_id: 1
    )
  end

  def build_client
    Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
  end

  test 'connect redirects to Google OAuth consent screen with a signed state' do
    admin = build_admin
    client = build_client
    sign_in admin

    get client_google_ads_connect_path(client)

    assert_response :redirect
    assert_match %r{\Ahttps://accounts\.google\.com/o/oauth2/v2/auth}, response.location
  end

  test 'callback stores the refresh token and marks the client as connected' do
    admin = build_admin
    client = build_client
    sign_in admin

    state = Rails.application.message_verifier(:google_ads_oauth_state).generate(client.id)
    response_double = FakeResponse.new(true, { 'refresh_token' => 'refresh-abc' })

    HTTParty.stub :post, response_double do
      get google_ads_callback_url(code: 'auth-code', state: state)
    end

    assert_redirected_to edit_client_path(client)
    client.reload
    assert_equal 'refresh-abc', client.google_ads_refresh_token
    assert client.google_ads_connected_at.present?
  end

  test 'callback rejects an invalid state' do
    admin = build_admin
    sign_in admin

    get google_ads_callback_url(code: 'auth-code', state: 'tampered')

    assert_redirected_to clients_path
    assert_equal 'Estado inválido na conexão com o Google Ads.', flash[:alert]
  end

  test 'disconnect clears the stored refresh token' do
    admin = build_admin
    client = build_client
    client.update!(google_ads_refresh_token: 'refresh-abc', google_ads_connected_at: Time.current)
    sign_in admin

    delete client_google_ads_disconnect_path(client)

    assert_redirected_to edit_client_path(client)
    client.reload
    assert_nil client.google_ads_refresh_token
    assert_nil client.google_ads_connected_at
  end
end
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `bin/rails test test/controllers/google_ads_controller_test.rb`
Expected: FAIL — routes/controller don't exist yet.

- [ ] **Step 4: Add the routes**

```ruby
# config/routes.rb — inside `scope '/painel' do`, right after the existing
# `get '/shopify/auth'` / `get '/shopify/callback'` lines
    get    'clients/:id/google_ads/connect',    to: 'google_ads#connect',    as: :client_google_ads_connect
    get    'google_ads/callback',                to: 'google_ads#callback',   as: :google_ads_callback
    delete 'clients/:id/google_ads/disconnect', to: 'google_ads#disconnect', as: :client_google_ads_disconnect
```

- [ ] **Step 5: Implement the controller**

```ruby
# app/controllers/google_ads_controller.rb
class GoogleAdsController < ApplicationController
  before_action :require_admin!

  AUTH_URL = 'https://accounts.google.com/o/oauth2/v2/auth'.freeze
  TOKEN_URL = 'https://oauth2.googleapis.com/token'.freeze
  SCOPE = 'https://www.googleapis.com/auth/adwords'.freeze

  def connect
    client = Client.find(params[:id])
    state = verifier.generate(client.id)

    redirect_to "#{AUTH_URL}?#{connect_params(state).to_query}", allow_other_host: true
  end

  def callback
    client_id = verifier.verify(params[:state])
    client = Client.find(client_id)

    response = HTTParty.post(
      TOKEN_URL,
      body: {
        client_id: ENV['GOOGLE_ADS_CLIENT_ID'],
        client_secret: ENV['GOOGLE_ADS_CLIENT_SECRET'],
        code: params[:code],
        grant_type: 'authorization_code',
        redirect_uri: google_ads_callback_url
      }
    )

    unless response.success? && response.parsed_response['refresh_token'].present?
      return redirect_to edit_client_path(client), alert: 'Não foi possível conectar ao Google Ads.'
    end

    client.update!(
      google_ads_refresh_token: response.parsed_response['refresh_token'],
      google_ads_connected_at: Time.current
    )

    redirect_to edit_client_path(client), notice: 'Google Ads conectado com sucesso.'
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
    redirect_to clients_path, alert: 'Estado inválido na conexão com o Google Ads.'
  end

  def disconnect
    client = Client.find(params[:id])
    client.update!(google_ads_refresh_token: nil, google_ads_connected_at: nil)
    redirect_to edit_client_path(client), notice: 'Google Ads desconectado.'
  end

  private

  def connect_params(state)
    {
      client_id: ENV['GOOGLE_ADS_CLIENT_ID'],
      redirect_uri: google_ads_callback_url,
      response_type: 'code',
      scope: SCOPE,
      access_type: 'offline',
      prompt: 'consent',
      state: state
    }
  end

  def verifier
    Rails.application.message_verifier(:google_ads_oauth_state)
  end
end
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bin/rails test test/controllers/google_ads_controller_test.rb`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add app/controllers/google_ads_controller.rb config/routes.rb test/test_helper.rb \
        test/controllers/google_ads_controller_test.rb
git commit -m "feat: add Google Ads OAuth connect/callback/disconnect flow"
```

---

### Task 10: Client admin form — dashboard toggle, Meta fields, Google Ads connect button

**Files:**
- Modify: `app/controllers/clients_controller.rb`
- Modify: `app/views/clients/_form.html.erb`
- Test: `test/controllers/clients_controller_test.rb`

**Interfaces:**
- Consumes: `Client` attributes from Tasks 1/2, `client_google_ads_connect_path`/
  `client_google_ads_disconnect_path` (Task 9).
- Produces: no new interface — admin-editable `sales_dashboard_enabled`,
  `meta_access_token`, `meta_ad_account_id`, `google_ads_customer_id`.

- [ ] **Step 1: Write the failing test**

```ruby
# test/controllers/clients_controller_test.rb
require 'test_helper'

class ClientsControllerTest < ActionDispatch::IntegrationTest
  def build_admin
    User.create!(
      name: 'Admin', email: "admin-#{SecureRandom.hex(4)}@example.com",
      password: 'password123', password_confirmation: 'password123', profile_id: 1
    )
  end

  test 'admin can enable the sales dashboard and set Meta/Google Ads fields' do
    admin = build_admin
    client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
    sign_in admin

    patch client_path(client), params: {
      client: {
        name: client.name,
        email: client.email,
        sales_dashboard_enabled: '1',
        meta_access_token: 'token123',
        meta_ad_account_id: 'act_1',
        google_ads_customer_id: '1234567890'
      }
    }

    client.reload
    assert client.sales_dashboard_enabled?
    assert_equal 'token123', client.meta_access_token
    assert_equal 'act_1', client.meta_ad_account_id
    assert_equal '1234567890', client.google_ads_customer_id
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/clients_controller_test.rb`
Expected: FAIL — the new params are silently dropped (not permitted), so
`sales_dashboard_enabled?`/`meta_access_token` stay unset.

- [ ] **Step 3: Permit the new params**

```ruby
# app/controllers/clients_controller.rb
  def client_params
    params.require(:client).permit(
      :name, :email, :active, :shopify_shop_url, :shopify_access_token,
      :zapi_instance_id, :zapi_instance_token, :zapi_client_token,
      :sales_dashboard_enabled, :meta_access_token, :meta_ad_account_id,
      :google_ads_customer_id
    )
  end
```

- [ ] **Step 4: Add the form sections**

Add right after the "Configurações Zapi" `</div>` (before the "Usuários Vinculados" block)
in `app/views/clients/_form.html.erb`:

```erb
        <%# Dashboard de Vendas %>
        <div class="cform-section">
          <div class="cform-section__header">
            <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" fill="none" viewBox="0 0 24 24" stroke-width="1.8" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" d="M3 13.5l3-3 4 4 8-8" />
              <path stroke-linecap="round" stroke-linejoin="round" d="M3 21h18" />
            </svg>
            Dashboard de Vendas
          </div>

          <div class="cform-field">
            <%= form.label :sales_dashboard_enabled, 'Dashboard de Vendas', class: 'cform-field__label' %>
            <div class="cform-toggle">
              <%= form.check_box :sales_dashboard_enabled, class: 'cform-toggle__input', disabled: read_only %>
              <span class="cform-toggle__label">Habilitado para este cliente</span>
            </div>
          </div>
        </div>

        <%# Integração Meta Ads %>
        <div class="cform-section">
          <div class="cform-section__header">
            <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" fill="none" viewBox="0 0 24 24" stroke-width="1.8" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" d="M12 3v18m9-9H3" />
            </svg>
            Integração Meta Ads
          </div>

          <div class="cform-row">
            <div class="cform-field">
              <%= form.label :meta_ad_account_id, 'ID da Conta de Anúncio', class: 'cform-field__label' %>
              <%= form.text_field :meta_ad_account_id, class: 'cform-field__input', placeholder: 'act_1234567890', disabled: read_only %>
            </div>
            <div class="cform-field">
              <%= form.label :meta_access_token, 'Token de Acesso', class: 'cform-field__label' %>
              <div class="cform-field__input-wrapper">
                <%= form.password_field :meta_access_token, class: 'cform-field__input cform-field__input--password', placeholder: client.meta_access_token.present? ? '••••••••••••••••' : 'Token de longa duração (System User)', disabled: read_only, value: '' %>
                <% if client.meta_access_token.present? %>
                  <span class="cform-field__badge cform-field__badge--success">Configurado</span>
                <% end %>
              </div>
              <span class="cform-field__hint">Deixe em branco para manter o token atual.</span>
            </div>
          </div>
        </div>

        <%# Integração Google Ads %>
        <div class="cform-section">
          <div class="cform-section__header">
            <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" fill="none" viewBox="0 0 24 24" stroke-width="1.8" stroke="currentColor">
              <circle cx="12" cy="12" r="9" />
            </svg>
            Integração Google Ads
          </div>

          <div class="cform-field">
            <%= form.label :google_ads_customer_id, 'Customer ID', class: 'cform-field__label' %>
            <%= form.text_field :google_ads_customer_id, class: 'cform-field__input', placeholder: '1234567890', disabled: read_only %>
            <span class="cform-field__hint">ID de 10 dígitos da conta Google Ads do cliente, sem hífens.</span>
          </div>

          <% if client.persisted? %>
            <% if client.google_ads_connected_at.present? %>
              <div class="cform-alert cform-alert--success">
                <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
                <span>Conectado em <%= l(client.google_ads_connected_at, format: :short) %>.</span>
                <%= button_to 'Desconectar', client_google_ads_disconnect_path(client), method: :delete, class: 'cform-btn cform-btn--secondary', form: { style: 'margin-left: auto;' } %>
              </div>
            <% else %>
              <%= link_to 'Conectar Google Ads', client_google_ads_connect_path(client), class: 'cform-btn cform-btn--primary' %>
            <% end %>
          <% end %>
        </div>

```

- [ ] **Step 5: Run test to verify it passes**

Run: `bin/rails test test/controllers/clients_controller_test.rb`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add app/controllers/clients_controller.rb app/views/clients/_form.html.erb \
        test/controllers/clients_controller_test.rb
git commit -m "feat: manage sales dashboard toggle and ad integrations from the client form"
```

---

### Task 11: `ClientScoped` concern and `SalesDashboardController`

**Files:**
- Create: `app/controllers/concerns/client_scoped.rb`
- Modify: `app/controllers/dashboard_controller.rb`
- Create: `app/controllers/sales_dashboard_controller.rb`
- Modify: `config/routes.rb`
- Test: `test/controllers/sales_dashboard_controller_test.rb`

**Interfaces:**
- Consumes: `Sales::MonthlyMetrics` (Task 5), `AdCostSyncJob` (Task 8),
  `Client#sales_dashboard_enabled?` (Task 1).
- Produces: `ClientScoped#current_client_id`/`#set_client` (shared by `DashboardController`
  and `SalesDashboardController`), route `sales_dashboard_path` (GET, `/painel/vendas`) and
  `sync_ad_costs_sales_dashboard_path` (POST).

- [ ] **Step 1: Extract `ClientScoped` from `DashboardController`**

```ruby
# app/controllers/concerns/client_scoped.rb
module ClientScoped
  extend ActiveSupport::Concern

  private

  def current_client_id
    if current_user.admin?
      session[:selected_client_id] || current_user.client_id
    else
      current_user.client_id
    end
  end

  def set_client
    @client = Client.find_by(id: current_client_id)

    unless @client
      @empty_state = true
      @empty_message = current_user.admin? ? 'Nenhum cliente selecionado. Selecione um cliente no menu superior.' : 'Você não está vinculado a nenhum cliente.'
    end
  end
end
```

Two precise edits to the existing `app/controllers/dashboard_controller.rb` (380 lines,
unchanged otherwise):

1. Change line 1 from:
   ```ruby
   class DashboardController < ApplicationController
   ```
   to:
   ```ruby
   class DashboardController < ApplicationController
     include ClientScoped

   ```
   (i.e. add `include ClientScoped` plus a blank line right after the class line, before
   the existing `before_action :authenticate_user!` on line 2).

2. Delete the `current_client_id` and `set_client` method definitions — currently lines
   38–54, immediately after the `private` keyword on line 36 and immediately before
   `def load_form_references` on line 55:
   ```ruby
   def current_client_id
     if current_user.admin?
       session[:selected_client_id] || current_user.client_id
     else
       current_user.client_id
     end
   end

   def set_client
     @client = Client.find_by(id: current_client_id)

     unless @client
       @empty_state = true
       @empty_message = current_user.admin? ? "Nenhum cliente selecionado. Selecione um cliente no menu superior." : "Você não está vinculado a nenhum cliente."
     end
   end

   ```
   Everything else in the file (`session_detail`, `load_form_references`,
   `fetch_top_products`, `calculate_avg_times`, `fetch_sessions`, etc.) stays exactly as
   it is — `ClientScoped` provides the two deleted methods with identical bodies.

- [ ] **Step 2: Run the existing dashboard tests to confirm the refactor didn't break anything**

Run: `bin/rails test`
Expected: PASS (no behavior change — this step has no new test of its own, it's a pure
extraction covered by whichever tests already exercise `DashboardController`; if none
exist yet, at minimum `bin/rails test` must still pass end-to-end)

- [ ] **Step 3: Write the failing tests for `SalesDashboardController`**

```ruby
# test/controllers/sales_dashboard_controller_test.rb
require 'test_helper'

class SalesDashboardControllerTest < ActionDispatch::IntegrationTest
  def build_user(admin: false, client: nil)
    User.create!(
      name: 'User', email: "user-#{SecureRandom.hex(4)}@example.com",
      password: 'password123', password_confirmation: 'password123',
      profile_id: admin ? 1 : 2, client: client
    )
  end

  test 'redirects a non-admin client user when the dashboard is disabled' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com", sales_dashboard_enabled: false)
    user = build_user(client: client)
    sign_in user

    get sales_dashboard_path

    assert_redirected_to painel_path
  end

  test 'allows a non-admin client user when the dashboard is enabled' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com", sales_dashboard_enabled: true)
    user = build_user(client: client)
    sign_in user

    get sales_dashboard_path

    assert_response :success
  end

  test 'always allows an admin regardless of the toggle' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com", sales_dashboard_enabled: false)
    admin = build_user(admin: true, client: client)
    sign_in admin

    get sales_dashboard_path

    assert_response :success
  end

  test 'renders the metrics for the requested month' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com", sales_dashboard_enabled: true)
    user = build_user(client: client)
    Order.create!(client: client, shopify_order_id: SecureRandom.hex(6), shopify_creation_date: Time.zone.local(2026, 3, 10), total_price: 250, subtotal_price: 250, total_discounts: 0)
    sign_in user

    get sales_dashboard_path(year: 2026, month: 3)

    assert_response :success
    assert_match 'R$ 250,00', response.body
  end
end
```

This app has no `rails-i18n` gem and no `number.currency` config in
`config/locales/pt-BR.yml`, so plain `number_to_currency(value)` renders in the `$1,234.56`
default format regardless of `I18n.default_locale`. Every existing view in this codebase
works around that by always passing `unit: 'R$ ', separator: ',', delimiter: '.'`
explicitly (see `app/views/dashboard/index.html.erb:999`). Steps 7 (Task 11) and 3 (Task 12)
below must do the same, or this assertion will fail.

- [ ] **Step 4: Run tests to verify they fail**

Run: `bin/rails test test/controllers/sales_dashboard_controller_test.rb`
Expected: FAIL — route/controller don't exist yet.

- [ ] **Step 5: Add the route**

```ruby
# config/routes.rb — inside `scope '/painel' do`, near `resources :dashboard`
    resources :sales_dashboard, only: [:index], path: 'vendas' do
      collection do
        post :sync_ad_costs
      end
    end
```

- [ ] **Step 6: Implement the controller**

```ruby
# app/controllers/sales_dashboard_controller.rb
class SalesDashboardController < ApplicationController
  include ClientScoped

  before_action :set_client
  before_action :ensure_dashboard_access!
  before_action :load_metrics, only: [:index]

  def index; end

  def sync_ad_costs
    unless @client
      return redirect_to sales_dashboard_path, alert: 'Nenhum cliente selecionado.'
    end

    year = params[:year].presence || Date.current.year
    month = params[:month].presence || Date.current.month

    results = AdCostSyncJob.new.perform(client_id: @client.id, year: year.to_i, month: month.to_i)

    if results.empty?
      redirect_to sales_dashboard_path(year: year, month: month), alert: 'Nenhuma integração de anúncio configurada para este cliente.'
    elsif results.any? { |r| r.status == :error }
      errors = results.select { |r| r.status == :error }.map(&:error_message).join('; ')
      redirect_to sales_dashboard_path(year: year, month: month), alert: "Falha ao sincronizar: #{errors}"
    else
      redirect_to sales_dashboard_path(year: year, month: month), notice: 'Custos sincronizados com sucesso.'
    end
  end

  private

  def ensure_dashboard_access!
    return if current_user.admin?
    return if @client&.sales_dashboard_enabled?

    redirect_to painel_path, alert: 'Dashboard de vendas não habilitado para este cliente.'
  end

  def load_metrics
    return unless @client

    @year = (params[:year].presence || Date.current.year).to_i
    @month = (params[:month].presence || Date.current.month).to_i
    @tag = params[:tag].presence

    @metrics = Sales::MonthlyMetrics.new(client: @client, year: @year, month: @month, tag: @tag).call
  end
end
```

- [ ] **Step 7: Add a minimal view so the controller test can render**

Create a placeholder now — Task 12 replaces it with the full designed page:

```erb
<%# app/views/sales_dashboard/index.html.erb %>
<% title 'Dashboard de Vendas' %>

<% if @empty_state %>
  <p><%= @empty_message %></p>
<% else %>
  <p>Faturamento: <%= number_to_currency(@metrics[:revenue], unit: 'R$ ', separator: ',', delimiter: '.') %></p>
<% end %>
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `bin/rails test test/controllers/sales_dashboard_controller_test.rb`
Expected: PASS

- [ ] **Step 9: Commit**

```bash
git add app/controllers/concerns/client_scoped.rb app/controllers/dashboard_controller.rb \
        app/controllers/sales_dashboard_controller.rb app/views/sales_dashboard/index.html.erb \
        config/routes.rb test/controllers/sales_dashboard_controller_test.rb
git commit -m "feat: add SalesDashboardController with per-client gating"
```

---

### Task 12: Sales dashboard view and navigation link

**Files:**
- Modify: `app/views/sales_dashboard/index.html.erb` (replace the Task 11 placeholder)
- Modify: `app/views/layouts/partials/_header.html.erb`
- Test: `test/controllers/sales_dashboard_controller_test.rb` (extend)

**Interfaces:**
- Consumes: `@metrics` hash (Task 5/11 — keys `:revenue, :gross_sales, :discounts,
  :orders_count, :avg_ticket, :conversion_rate, :ad_cost, :ad_cost_available,
  :configured_platforms, :roas, :new_customers_count, :cac`), `@year`, `@month`, `@tag`,
  `@client`.
- Produces: no new interface — this is the final user-facing page for the feature.

- [ ] **Step 1: Extend the controller test with a KPI-content assertion**

```ruby
# test/controllers/sales_dashboard_controller_test.rb — add inside the class
  test 'shows a not-synced warning when a platform is configured but has no snapshot yet' do
    client = Client.create!(
      name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com", sales_dashboard_enabled: true,
      meta_access_token: 'token', meta_ad_account_id: 'act_1'
    )
    user = build_user(client: client)
    sign_in user

    get sales_dashboard_path(year: 2026, month: 3)

    assert_response :success
    assert_match 'Custos de anúncio não configurados', response.body
  end

  test 'shows a no-integration warning when no ad platform is configured at all' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com", sales_dashboard_enabled: true)
    user = build_user(client: client)
    sign_in user

    get sales_dashboard_path(year: 2026, month: 3)

    assert_response :success
    assert_match 'Nenhuma integração de anúncio configurada', response.body
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/sales_dashboard_controller_test.rb`
Expected: FAIL — the placeholder view from Task 11 doesn't render that copy.

- [ ] **Step 3: Write the full view**

```erb
<%# app/views/sales_dashboard/index.html.erb %>
<% title 'Dashboard de Vendas' %>

<style>
  .sd-page { padding: 24px 28px; min-height: 100vh; }
  .sd-header { display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 16px; margin-bottom: 24px; background: #3b4adf; border-radius: 14px; padding: 18px 24px; }
  .sd-header__title { font-size: 20px; font-weight: 800; color: #fff; }
  .sd-header__subtitle { font-size: 13px; color: #dbe0ff; }
  .sd-month-nav { display: flex; align-items: center; gap: 10px; }
  .sd-month-nav__btn { background: #fff; color: #3b4adf; border-radius: 8px; padding: 6px 12px; text-decoration: none; font-weight: 600; font-size: 13px; }
  .sd-month-nav__label { color: #fff; font-weight: 700; min-width: 140px; text-align: center; }
  .sd-tag-filter { margin-bottom: 20px; }
  .sd-tag-filter input { border: 1px solid #e4e7f0; border-radius: 8px; padding: 8px 12px; font-size: 13px; }
  .sd-tag-filter button { border: none; background: #3b4adf; color: #fff; border-radius: 8px; padding: 8px 14px; font-size: 13px; font-weight: 600; margin-left: 6px; }
  .sd-kpi-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 16px; margin-bottom: 24px; }
  .sd-kpi { background: #fff; border: 1px solid #e4e7f0; border-radius: 12px; padding: 18px; }
  .sd-kpi__label { font-size: 12px; color: #9097b5; text-transform: uppercase; letter-spacing: 0.04em; font-weight: 600; }
  .sd-kpi__value { font-size: 26px; font-weight: 800; color: #1e2235; margin-top: 6px; }
  .sd-kpi__hint { font-size: 12px; color: #9097b5; margin-top: 4px; }
  .sd-alert { display: flex; align-items: center; justify-content: space-between; gap: 12px; background: #fef3c7; color: #92400e; border-radius: 10px; padding: 14px 18px; margin-bottom: 20px; font-size: 14px; }
  .sd-alert button { border: none; background: #92400e; color: #fff; border-radius: 8px; padding: 8px 14px; font-size: 13px; font-weight: 600; cursor: pointer; }
</style>

<div class="sd-page">
  <div class="sd-header">
    <div>
      <div class="sd-header__title">Dashboard de Vendas<%= " — #{@client.name}" if @client %></div>
      <div class="sd-header__subtitle">Ticket médio, faturamento, conversão, ROAS e CAC do mês</div>
    </div>

    <% if @client %>
      <% current_month = Date.new(@year, @month, 1) %>
      <div class="sd-month-nav">
        <%= link_to '‹', sales_dashboard_path(year: (current_month - 1.month).year, month: (current_month - 1.month).month, tag: @tag), class: 'sd-month-nav__btn' %>
        <span class="sd-month-nav__label"><%= month_label(current_month) %></span>
        <%= link_to '›', sales_dashboard_path(year: (current_month + 1.month).year, month: (current_month + 1.month).month, tag: @tag), class: 'sd-month-nav__btn' %>
      </div>
    <% end %>
  </div>

  <% if @empty_state %>
    <p><%= @empty_message %></p>
  <% else %>
    <div class="sd-tag-filter">
      <%= form_with url: sales_dashboard_path, method: :get, local: true do %>
        <%= hidden_field_tag :year, @year %>
        <%= hidden_field_tag :month, @month %>
        <%= text_field_tag :tag, @tag, placeholder: 'Filtrar por tag (ex.: VendedoraElo)' %>
        <%= button_tag 'Filtrar' %>
      <% end %>
    </div>

    <% unless @metrics[:ad_cost_available] %>
      <div class="sd-alert">
        <span>
          <% if @metrics[:configured_platforms].empty? %>
            Nenhuma integração de anúncio configurada para este cliente.
          <% else %>
            Custos de anúncio não configurados para este mês.
          <% end %>
        </span>
        <% if current_user.admin? && @metrics[:configured_platforms].any? %>
          <%= button_to 'Sincronizar custos', sync_ad_costs_sales_dashboard_path(year: @year, month: @month), method: :post %>
        <% end %>
      </div>
    <% end %>

    <div class="sd-kpi-grid">
      <div class="sd-kpi">
        <div class="sd-kpi__label">Ticket Médio</div>
        <div class="sd-kpi__value"><%= @metrics[:avg_ticket] ? currency(@metrics[:avg_ticket]) : '—' %></div>
      </div>

      <div class="sd-kpi">
        <div class="sd-kpi__label">Faturamento</div>
        <div class="sd-kpi__value"><%= currency(@metrics[:revenue]) %></div>
        <div class="sd-kpi__hint">Bruto: <%= currency(@metrics[:gross_sales]) %> · Descontos: <%= currency(@metrics[:discounts]) %></div>
      </div>

      <div class="sd-kpi">
        <div class="sd-kpi__label">Taxa de Conversão</div>
        <div class="sd-kpi__value"><%= @metrics[:conversion_rate] ? "#{@metrics[:conversion_rate]}%" : '—' %></div>
      </div>

      <div class="sd-kpi">
        <div class="sd-kpi__label">ROAS Faturado</div>
        <div class="sd-kpi__value"><%= @metrics[:roas] ? "#{@metrics[:roas]}x" : '—' %></div>
      </div>

      <div class="sd-kpi">
        <div class="sd-kpi__label">CAC</div>
        <div class="sd-kpi__value"><%= @metrics[:cac] ? currency(@metrics[:cac]) : '—' %></div>
        <div class="sd-kpi__hint"><%= @metrics[:new_customers_count] %> clientes novos</div>
      </div>
    </div>
  <% end %>
</div>
```

`currency` and `month_label` are small local helpers (same inline-`def` pattern already
used in `app/views/dashboard/index.html.erb:808`, `def calc_change`). `currency` applies
this app's Brazilian-Real formatting consistently instead of repeating the options on
every call. `month_label` is hardcoded to Portuguese month names rather than using
`I18n.l(date, format: '%B/%Y')`, because `config/locales/pt-BR.yml` has no `date.month_names`
translation — the existing month picker in `app/views/dashboard/index.html.erb:769`
sidesteps the same gap by rendering `Date::MONTHNAMES` (which are English) as raw text; this
page avoids repeating that gap. Add both right after the `<style>` block, before the
`<div class="sd-page">`:

```erb
<%
  def currency(value) = number_to_currency(value, unit: 'R$ ', separator: ',', delimiter: '.')

  def month_label(date)
    names = %w[janeiro fevereiro março abril maio junho julho agosto setembro outubro novembro dezembro]
    "#{names[date.month - 1]}/#{date.year}"
  end
%>
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/controllers/sales_dashboard_controller_test.rb`
Expected: PASS

- [ ] **Step 5: Add the "Vendas" nav link**

```erb
<%# app/views/layouts/partials/_header.html.erb — right after the existing "DASHBOARD" link (line 32) %>
      <% if current_user.admin? || current_user.client&.sales_dashboard_enabled? %>
        <%= link_to sales_dashboard_path, class: "crm-header__nav-link #{'active' if current_page?(sales_dashboard_path)}" do %>
          <i class="fa-solid fa-sack-dollar crm-fa"></i>
          Vendas
        <% end %>
      <% end %>
```

This goes inside the `<% else %>` branch that already wraps the "DASHBOARD" link (i.e. it's
still hidden for affiliates), right after that link's `<% end %>` on line 32.

- [ ] **Step 6: Run the full test suite**

Run: `bin/rails test`
Expected: PASS (all green)

- [ ] **Step 7: Commit**

```bash
git add app/views/sales_dashboard/index.html.erb app/views/layouts/partials/_header.html.erb \
        test/controllers/sales_dashboard_controller_test.rb
git commit -m "feat: build the sales dashboard page and add its nav link"
```

---

## Post-implementation checklist (manual, not automated)

- [ ] Generate production Active Record Encryption keys (different from dev/test) and set
  `AR_ENCRYPTION_PRIMARY_KEY`, `AR_ENCRYPTION_DETERMINISTIC_KEY`,
  `AR_ENCRYPTION_KEY_DERIVATION_SALT` as Heroku config vars before deploying Task 2.
- [ ] Register a Google Cloud OAuth client (Web application type) with redirect URI
  `https://<production-host>/painel/google_ads/callback`, and set `GOOGLE_ADS_CLIENT_ID`
  / `GOOGLE_ADS_CLIENT_SECRET` as Heroku config vars.
  Register the equivalent `http://localhost:3000/painel/google_ads/callback` redirect URI
  for local testing.
- [ ] Apply for a Google Ads Developer Token (Basic Access) and set
  `GOOGLE_ADS_DEVELOPER_TOKEN` — this approval is external to this codebase and can take
  from hours to days.
- [ ] For each client that will use the dashboard: get the Meta System User long-lived
  token and Ad Account ID from the client's Business Manager, and re-sync historical
  orders (`Shopify::Orders.sync_shopify_orders_to_rails(session:, client:, time_range: :all)`)
  so `tags`/`subtotal_price`/`total_discounts`/`total_price`/`cancelled_at` are backfilled.
