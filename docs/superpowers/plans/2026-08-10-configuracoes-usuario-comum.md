# Configurações da própria loja para usuário comum — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a non-admin user view and edit the settings of their own client (Shopify, Zapi, Meta Ads, Google Ads, sales-dashboard toggle) at a dedicated `/painel/configuracoes` page, scoped strictly to `current_user.client`, without touching admin-only capabilities (`active` toggle, other clients, linked-users management).

**Architecture:** New `SettingsController` (edit/update) always resolves `@client` from `current_user.client` — never from a URL param — and reuses the existing `clients/_form` partial. That partial gets two new `current_user.admin?` guards to hide the `active` toggle and the linked-users list from non-admins. `GoogleAdsController`'s blanket admin check becomes a per-client check (`admin? || current_user.client_id == client.id`) so a common user can connect/disconnect Google Ads for their own client, with redirects routed to the right edit page per role. Two small UX hooks (header link, sales-dashboard CTA) point common users at the new page.

**Tech Stack:** Ruby on Rails 7, Minitest (`ActionDispatch::IntegrationTest`), Devise test helpers, existing `Profile::ADMIN` / `Profile::USER` constants.

## Global Constraints

- Common users may only ever read/write **their own** client (`current_user.client`) — never another client's data, regardless of URL params.
- The `active` field (client enabled/disabled) stays admin-only.
- No changes to `ClientsController` behavior — admin flows must keep working exactly as today.
- Follow the existing per-test-file `build_admin`/`build_user` fixture-creation convention (profiles aren't seeded via fixtures; each test file creates the `Profile` row it needs via `find_or_create_by!`).

---

### Task 1: `SettingsController` — route, controller, view, tests

**Files:**
- Modify: `config/routes.rb:44-51` (add the new resource route next to the existing `google_ads`/`sales_dashboard` routes)
- Create: `app/controllers/settings_controller.rb`
- Create: `app/views/settings/edit.html.erb`
- Test: `test/controllers/settings_controller_test.rb`

**Interfaces:**
- Produces: route helpers `edit_settings_path` (GET) and `settings_path` (PATCH), used by Task 3 (redirects) and Task 4 (links).
- Produces: `SettingsController#client_params` permitted list (all `Client` attributes writable via this controller, `:active` excluded) — Task 2 does not touch this, listed here for reference only.

- [ ] **Step 1: Write the failing tests**

Create `test/controllers/settings_controller_test.rb`:

```ruby
require 'test_helper'

class SettingsControllerTest < ActionDispatch::IntegrationTest
  def build_user(admin: false, client: nil)
    # No profiles.yml fixture exists, so the referenced profile (id 1 = admin,
    # id 2 = regular user, per Profile::ADMIN/Profile::USER) must be created
    # here to satisfy the users.profile_id foreign key constraint.
    profile_id = admin ? Profile::ADMIN : Profile::USER
    Profile.find_or_create_by!(id: profile_id) { |p| p.name = admin ? 'Admin' : 'User' }

    User.create!(
      name: 'User', email: "user-#{SecureRandom.hex(4)}@example.com",
      password: 'password123', password_confirmation: 'password123',
      profile_id: profile_id, client: client
    )
  end

  test 'a user without a linked client is redirected with an alert' do
    user = build_user
    sign_in user

    get edit_settings_path

    assert_redirected_to painel_path
    assert_equal 'Você não está vinculado a nenhum cliente.', flash[:alert]
  end

  test 'a common user can view their own client settings' do
    client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
    user = build_user(client: client)
    sign_in user

    get edit_settings_path

    assert_response :success
    assert_match client.name, response.body
  end

  test 'a common user can update Meta Ads and Google Ads fields for their own client' do
    client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
    user = build_user(client: client)
    sign_in user

    patch settings_path, params: {
      client: {
        name: client.name,
        email: client.email,
        meta_access_token: 'token123',
        meta_ad_account_id: 'act_1',
        google_ads_customer_id: '1234567890'
      }
    }

    assert_redirected_to edit_settings_path
    client.reload
    assert_equal 'token123', client.meta_access_token
    assert_equal 'act_1', client.meta_ad_account_id
    assert_equal '1234567890', client.google_ads_customer_id
  end

  test 'a common user cannot change the active flag of their own client' do
    client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com", active: true)
    user = build_user(client: client)
    sign_in user

    patch settings_path, params: {
      client: { name: client.name, email: client.email, active: '0' }
    }

    assert client.reload.active?
  end

  test 'a common user always edits their own client no matter what other client exists' do
    other_client = Client.create!(name: 'Outra Loja', email: "outra-#{SecureRandom.hex(4)}@example.com")
    client = Client.create!(name: 'Minha Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    user = build_user(client: client)
    sign_in user

    get edit_settings_path

    assert_response :success
    assert_match 'Minha Loja', response.body
    assert_no_match 'Outra Loja', response.body
  end

  test 'submitting a blank meta_access_token preserves the existing stored token' do
    client = Client.create!(
      name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com",
      meta_access_token: 'existing-token', meta_ad_account_id: 'act_1'
    )
    user = build_user(client: client)
    sign_in user

    patch settings_path, params: {
      client: { name: client.name, email: client.email, meta_access_token: '' }
    }

    assert_equal 'existing-token', client.reload.meta_access_token
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/settings_controller_test.rb`
Expected: FAIL — no route matches `edit_settings_path` / `settings_path` (`ActionController::UrlGenerationError` or similar), since neither the route nor the controller exist yet.

- [ ] **Step 3: Add the route**

In `config/routes.rb`, right after the existing `sales_dashboard` routes (currently lines 50-51: `get 'vendas', ...` / `post 'vendas/sync_ad_costs', ...`), add:

```ruby
    resource :settings, path: 'configuracoes', controller: 'settings', only: [:edit, :update]
```

- [ ] **Step 4: Create `SettingsController`**

Create `app/controllers/settings_controller.rb`:

```ruby
class SettingsController < ApplicationController
  before_action :set_client

  def edit; end

  def update
    params[:client].delete(:meta_access_token) if params[:client][:meta_access_token].blank?

    if @client.update(client_params)
      redirect_to edit_settings_path, notice: 'Configurações atualizadas com sucesso.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_client
    @client = current_user.client

    unless @client
      redirect_to painel_path, alert: 'Você não está vinculado a nenhum cliente.'
    end
  end

  def client_params
    params.require(:client).permit(
      :name, :email, :shopify_shop_url, :shopify_access_token,
      :zapi_instance_id, :zapi_instance_token, :zapi_client_token,
      :sales_dashboard_enabled, :meta_access_token, :meta_ad_account_id,
      :google_ads_customer_id
    )
  end
end
```

- [ ] **Step 5: Create the view**

Create `app/views/settings/edit.html.erb`:

```erb
<% title 'Configurações' %>
<%= render 'clients/form', client: @client, read_only: false %>
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bin/rails test test/controllers/settings_controller_test.rb`
Expected: PASS (all 6 tests).

- [ ] **Step 7: Commit**

```bash
git add config/routes.rb app/controllers/settings_controller.rb app/views/settings/edit.html.erb test/controllers/settings_controller_test.rb
git commit -m "feat: add self-service client settings page for common users"
```

---

### Task 2: Hide admin-only sections in the shared `clients/_form` partial

**Files:**
- Modify: `app/views/clients/_form.html.erb:58-64` (Status/active block) and `:244-272` (Usuários Vinculados block)
- Test: `test/controllers/settings_controller_test.rb` (extend), `test/controllers/clients_controller_test.rb` (extend)

**Interfaces:**
- Consumes: `current_user` (already available in every view via Devise), `client.persisted?`, `client.users` (from `Client` model, unchanged).
- No new interfaces produced — this task only changes what's rendered.

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/settings_controller_test.rb`:

```ruby
  test 'a common user does not see the active toggle or linked users list' do
    client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
    user = build_user(client: client)
    sign_in user

    get edit_settings_path

    assert_response :success
    assert_no_match 'Cliente ativo', response.body
    assert_no_match 'Usuários Vinculados', response.body
  end
```

Add to `test/controllers/clients_controller_test.rb`:

```ruby
  test 'admin still sees the active toggle when editing a client' do
    admin = build_admin
    client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
    sign_in admin

    get edit_client_path(client)

    assert_response :success
    assert_match 'Cliente ativo', response.body
  end
```

- [ ] **Step 2: Run tests to verify the new one fails**

Run: `bin/rails test test/controllers/settings_controller_test.rb -n test_a_common_user_does_not_see_the_active_toggle_or_linked_users_list`
Expected: FAIL — both `Cliente ativo` and `Usuários Vinculados` currently render for every role.

- [ ] **Step 3: Gate the Status block**

In `app/views/clients/_form.html.erb`, wrap the existing Status block (lines 58-64):

```erb
          <div class="cform-field">
            <%= form.label :active, 'Status', class: 'cform-field__label' %>
            <div class="cform-toggle">
              <%= form.check_box :active, class: 'cform-toggle__input', disabled: read_only %>
              <span class="cform-toggle__label">Cliente ativo</span>
            </div>
          </div>
```

with a `current_user.admin?` guard:

```erb
          <% if current_user.admin? %>
            <div class="cform-field">
              <%= form.label :active, 'Status', class: 'cform-field__label' %>
              <div class="cform-toggle">
                <%= form.check_box :active, class: 'cform-toggle__input', disabled: read_only %>
                <span class="cform-toggle__label">Cliente ativo</span>
              </div>
            </div>
          <% end %>
```

- [ ] **Step 4: Gate the Usuários Vinculados block**

In the same file, the block currently starts with:

```erb
        <%# Usuários Vinculados (somente em edição) %>
        <% if client.persisted? && client.users.any? %>
```

Change the condition to also require admin:

```erb
        <%# Usuários Vinculados (somente em edição, admin) %>
        <% if current_user.admin? && client.persisted? && client.users.any? %>
```

(The rest of that block — through its closing `<% end %>` — is unchanged.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `bin/rails test test/controllers/settings_controller_test.rb test/controllers/clients_controller_test.rb`
Expected: PASS (full suite for both files).

- [ ] **Step 6: Commit**

```bash
git add app/views/clients/_form.html.erb test/controllers/settings_controller_test.rb test/controllers/clients_controller_test.rb
git commit -m "feat: hide admin-only client fields from the self-service settings form"
```

---

### Task 3: Per-client authorization in `GoogleAdsController`

**Files:**
- Modify: `app/controllers/google_ads_controller.rb` (whole file — see below)
- Test: `test/controllers/google_ads_controller_test.rb` (extend)

**Interfaces:**
- Consumes: `edit_settings_path` (Task 1), `edit_client_path` (existing).
- Produces: nothing consumed elsewhere — this task only changes authorization/redirect behavior.

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/google_ads_controller_test.rb` (add a `build_user` helper alongside the existing `build_admin`, then new tests):

```ruby
  def build_user(client: nil)
    Profile.find_or_create_by!(id: Profile::USER) { |p| p.name = 'User' }

    User.create!(
      name: 'User', email: "user-#{SecureRandom.hex(4)}@example.com",
      password: 'password123', password_confirmation: 'password123',
      profile_id: Profile::USER, client: client
    )
  end

  test 'a common user can connect Google Ads for their own client' do
    client = build_client
    user = build_user(client: client)
    sign_in user

    get client_google_ads_connect_path(client)

    assert_response :redirect
    assert_match %r{\Ahttps://accounts\.google\.com/o/oauth2/v2/auth}, response.location
  end

  test 'a common user cannot connect Google Ads for another client' do
    client = build_client
    other_client = build_client
    user = build_user(client: client)
    sign_in user

    get client_google_ads_connect_path(other_client)

    assert_redirected_to root_path
  end

  test 'callback redirects a common user to their own settings page' do
    client = build_client
    user = build_user(client: client)
    sign_in user

    state = Rails.application.message_verifier(:google_ads_oauth_state).generate(client.id)
    response_double = FakeResponse.new(true, { 'refresh_token' => 'refresh-abc' })

    HTTParty.stub :post, response_double do
      get google_ads_callback_url(code: 'auth-code', state: state)
    end

    assert_redirected_to edit_settings_path
    client.reload
    assert_equal 'refresh-abc', client.google_ads_refresh_token
  end

  test 'callback rejects a common user completing another client state' do
    client = build_client
    other_client = build_client
    user = build_user(client: client)
    sign_in user

    state = Rails.application.message_verifier(:google_ads_oauth_state).generate(other_client.id)

    get google_ads_callback_url(code: 'auth-code', state: state)

    assert_redirected_to root_path
    assert_nil other_client.reload.google_ads_refresh_token
  end

  test 'a common user can disconnect Google Ads for their own client' do
    client = build_client
    client.update!(google_ads_refresh_token: 'refresh-abc', google_ads_connected_at: Time.current)
    user = build_user(client: client)
    sign_in user

    delete client_google_ads_disconnect_path(client)

    assert_redirected_to edit_settings_path
    assert_nil client.reload.google_ads_refresh_token
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/google_ads_controller_test.rb`
Expected: FAIL on the new tests — `require_admin!` currently redirects every non-admin to `root_path`, so `connect`/`disconnect`/`callback` never succeed for a common user, and `callback` doesn't check any per-client authorization at all yet.

- [ ] **Step 3: Rewrite `GoogleAdsController`**

Replace `app/controllers/google_ads_controller.rb` entirely with:

```ruby
class GoogleAdsController < ApplicationController
  before_action :set_client, only: [:connect, :disconnect]
  before_action :authorize_client_owner!, only: [:connect, :disconnect]

  AUTH_URL = 'https://accounts.google.com/o/oauth2/v2/auth'.freeze
  TOKEN_URL = 'https://oauth2.googleapis.com/token'.freeze
  SCOPE = 'https://www.googleapis.com/auth/adwords'.freeze
  STATE_EXPIRY = 15.minutes

  def connect
    state = verifier.generate(@client.id, expires_in: STATE_EXPIRY)

    redirect_to "#{AUTH_URL}?#{connect_params(state).to_query}", allow_other_host: true
  end

  def callback
    client_id = verifier.verify(params[:state])
    client = Client.find(client_id)

    unless authorized_for?(client)
      return redirect_to root_path, alert: 'Acesso restrito.'
    end

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
      return redirect_to settings_return_path(client), alert: 'Não foi possível conectar ao Google Ads.'
    end

    client.update!(
      google_ads_refresh_token: response.parsed_response['refresh_token'],
      google_ads_connected_at: Time.current
    )

    redirect_to settings_return_path(client), notice: 'Google Ads conectado com sucesso.'
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
    redirect_to clients_path, alert: 'Estado inválido na conexão com o Google Ads.'
  end

  def disconnect
    @client.update!(google_ads_refresh_token: nil, google_ads_connected_at: nil)
    redirect_to settings_return_path(@client), notice: 'Google Ads desconectado.'
  end

  private

  def set_client
    @client = Client.find(params[:id])
  end

  def authorize_client_owner!
    return if authorized_for?(@client)

    redirect_to root_path, alert: 'Acesso restrito.'
  end

  def authorized_for?(client)
    current_user.admin? || current_user.client_id == client.id
  end

  def settings_return_path(client)
    current_user.admin? ? edit_client_path(client) : edit_settings_path
  end

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

Note the `clients_path` fallback in the `rescue` branch and the `redirect_to root_path, alert: 'Acesso restrito.'` in `callback`'s explicit denial both stay reachable for a common user (no `edit_client_path`/admin-only route is used in a path a common user can hit).

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/controllers/google_ads_controller_test.rb`
Expected: PASS (all tests, old and new — the pre-existing admin tests keep passing unchanged since `settings_return_path` resolves to `edit_client_path` for admins, matching the old hardcoded behavior).

- [ ] **Step 5: Commit**

```bash
git add app/controllers/google_ads_controller.rb test/controllers/google_ads_controller_test.rb
git commit -m "feat: authorize Google Ads connect/disconnect per client instead of admin-only"
```

---

### Task 4: UX entry points — header link and sales-dashboard CTA

**Files:**
- Modify: `app/views/layouts/partials/_header.html.erb:159-196` (user dropdown)
- Modify: `app/views/sales_dashboard/index.html.erb:20` (style block) and `:53-66` (alert block)
- Test: `test/controllers/sales_dashboard_controller_test.rb` (extend)

**Interfaces:**
- Consumes: `edit_settings_path` (Task 1), `edit_client_path` (existing), `Profile::AFFILIATE` (existing constant).

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/sales_dashboard_controller_test.rb`:

```ruby
  test 'the no-integration warning links a common user to their own settings page' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com", sales_dashboard_enabled: true)
    user = build_user(client: client)
    sign_in user

    get sales_dashboard_path(year: 2026, month: 3)

    assert_response :success
    assert_match %r{href="#{Regexp.escape(edit_settings_path)}"}, response.body
  end

  test 'the no-integration warning links an admin to the client edit page' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com", sales_dashboard_enabled: true)
    admin = build_user(admin: true, client: client)
    sign_in admin

    get sales_dashboard_path(year: 2026, month: 3)

    assert_response :success
    assert_match %r{href="#{Regexp.escape(edit_client_path(client))}"}, response.body
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/sales_dashboard_controller_test.rb`
Expected: FAIL on the two new tests — no link to either path exists yet in the empty-state alert.

- [ ] **Step 3: Add the sales-dashboard CTA link**

In `app/views/sales_dashboard/index.html.erb`, update the empty-integration branch (currently lines 55-61):

```erb
        <span>
          <% if @metrics[:configured_platforms].empty? %>
            Nenhuma integração de anúncio configurada para este cliente.
          <% else %>
            Custos de anúncio não configurados para este mês.
          <% end %>
        </span>
```

to:

```erb
        <span>
          <% if @metrics[:configured_platforms].empty? %>
            Nenhuma integração de anúncio configurada para este cliente.
            <%= link_to 'Configurar integração', current_user.admin? ? edit_client_path(@client) : edit_settings_path, class: 'sd-alert__link' %>
          <% else %>
            Custos de anúncio não configurados para este mês.
          <% end %>
        </span>
```

Add a matching style rule to the `<style>` block at the top of the file (near the existing `.sd-alert` rules, currently around line 20):

```css
  .sd-alert__link { color: #92400e; font-weight: 700; text-decoration: underline; margin-left: 8px; }
```

- [ ] **Step 4: Add the header "Configurações" link**

In `app/views/layouts/partials/_header.html.erb`, inside the `crm-header__dropdown` block, right after the closing `<% end %>` of the `if current_user.admin?` section (currently line 196, immediately before the `Sair` link), add an `elsif` branch to that same conditional. The existing structure is:

```erb
        <% if current_user.admin? %>
          <%= link_to users_path, class: 'crm-header__dropdown-item' do %>
            ...
          <% end %>
          <div class="crm-header__dropdown-sep"></div>
        <% end %>

        <%= link_to destroy_user_session_path,
```

Change the `<% if current_user.admin? %> ... <% end %>` to:

```erb
        <% if current_user.admin? %>
          <%= link_to users_path, class: 'crm-header__dropdown-item' do %>
            <i class="fa-solid fa-user crm-fa"></i>
            Usuários
          <% end %>

          <%= link_to clients_path, class: 'crm-header__dropdown-item' do %>
            <i class="fa-solid fa-building crm-fa"></i>
            Clientes
          <% end %>

          <%= link_to profiles_path, class: 'crm-header__dropdown-item' do %>
            <i class="fa-solid fa-id-badge crm-fa"></i>
            Perfis
          <% end %>

          <%= link_to '/painel/sidekiq', class: 'crm-header__dropdown-item', target: '_blank' do %>
            <i class="fa-solid fa-bolt crm-fa"></i>
            Sidekiq
          <% end %>

          <% if current_user&.profile_id == 1 %>
            <%= link_to try_on_index_path, class: "crm-header__dropdown-link #{'active' if request.path.start_with?(try_on_index_path)}" do %>
              <i class="fa-solid fa-wand-magic-sparkles crm-fa"></i>
              Try-On Virtual
            <% end %>
          <% end %>
          <div class="crm-header__dropdown-sep"></div>
        <% elsif current_user.profile_id != Profile::AFFILIATE %>
          <%= link_to edit_settings_path, class: 'crm-header__dropdown-item' do %>
            <i class="fa-solid fa-gear crm-fa"></i>
            Configurações
          <% end %>
          <div class="crm-header__dropdown-sep"></div>
        <% end %>
```

(Only the `if`/`end` boundaries change — every existing admin item inside stays exactly as-is; the new `elsif` branch is added as a sibling.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `bin/rails test test/controllers/sales_dashboard_controller_test.rb`
Expected: PASS (full suite).

Then run the full suite once to confirm nothing else broke:

Run: `bin/rails test`
Expected: PASS (all tests across the app).

- [ ] **Step 6: Commit**

```bash
git add app/views/sales_dashboard/index.html.erb app/views/layouts/partials/_header.html.erb test/controllers/sales_dashboard_controller_test.rb
git commit -m "feat: link common users to the self-service settings page from the header and sales dashboard"
```
