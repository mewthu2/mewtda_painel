# Rename /painel → /crm + Nova Página Institucional + Fundação do Redesign Visual — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mover o app hoje em `/painel` para `/crm`, liberar `/` para uma página institucional pública, e aplicar o redesign visual completo definido no spec `docs/superpowers/specs/2026-08-09-visual-redesign-design.md` — tokens de cor, dark mode, componentes base, topbar + sidebar, footer, página institucional, e a migração de todas as views autenticadas (dashboard, vendas, operações, marketing, admin, eventos, try-on) e do fluxo Devise completo para o novo design system.

**Architecture:** Rails 7 (Sprockets/SCSS, importmap, Devise, Turbo). Rotas: `root` passa de `redirect('/painel')` para `home#index` (público); o `scope '/painel'` vira `scope '/crm'` com a rota nomeada `:painel` renomeada para `:crm`. CSS: substitui blocos `<style>` inline por SCSS organizado em `app/assets/stylesheets/{tokens,layouts/*,components/*,pages/*}.scss`, usando CSS custom properties para permitir dark mode via classe `.theme-dark` em `<html>`, sem coluna nova no banco (persistido em `localStorage`). Depois de a fundação (tokens/componentes/topbar/sidebar) estar no ar, cada view autenticada existente é migrada individualmente: o bloco `<style>` inline é extraído para um arquivo `pages/<nome>.scss` (valores fixos trocados por tokens) e elementos puramente visuais (botões, inputs, tabelas, badges de status) trocam suas classes Bootstrap/bespoke pelas classes `.crm-*` compartilhadas, sem alterar HTML/JS funcional (DataTables, Chosen, modais Bootstrap).

**Tech Stack:** Ruby on Rails 7, Sprockets + SCSS, Devise, Turbo, Stimulus/importmap (não usado para o toggle de tema — script inline puro para evitar flash), Google Fonts (`Google Sans Flex`), Font Awesome (já presente via `admin.scss`).

## Global Constraints

- **Tokens de design** (definidos em `tokens.scss`, claro/escuro):
  | Token | Claro | Escuro |
  |---|---|---|
  | `--primary` | `#1967d2` | `#47b0f8` |
  | `--bg` | `#ffffff` | `#121317` |
  | `--fg` | `#212121` | `#dcdcdc` |
  | `--fg-alt` | `#6a6f71` | `#a8acad` |
  | `--chrome-bg` (não inverte) | `#1c2834` | `#0c1116` |
  | `--chrome-fg` | `#F3F4F6` | `#F3F4F6` |
  | `--outline` | `#e7e8ed` | `#2c313a` |
  | `--primary-tint` | `rgba(25,103,210,.08)` | `rgba(71,176,248,.12)` |
  | `--radius` | `0.45rem` | `0.45rem` |
- **Tipografia:** `'Google Sans Flex', 'Roboto', ui-sans-serif, sans-serif`, via Google Fonts (`family=Google+Sans+Flex:opsz,wght@6..72,400..700`).
- **Sem redirect de compatibilidade** para `/painel/*` — a URL antiga simplesmente deixa de existir (decisão explícita do usuário).
- **Sidebar/topbar**: os grupos e itens de navegação são exatamente os que já existem hoje em `_header.html.erb` (Dashboard, Vendas, Operações > Pedidos/Clientes/Produtos, Marketing > Campanhas/Afiliados/Automações, Admin > Usuários/Clientes/Perfis/Sidekiq/Try-On Virtual), incluindo o link morto "Automações" e a duplicidade de nome "Clientes" — mantidos como estão, fora de escopo.
- **Bootstrap 5, jQuery, DataTables continuam em uso** onde já são usados — este trabalho não reescreve JS/framework, só aparência e roteamento.
- **Escopo completo:** este plano cobre rotas, fundação de design system E a migração visual de todas as views autenticadas + fluxo Devise completo (Tasks 16-50), fechando com uma verificação final end-to-end (Tasks 51-52).

---

### Task 1: Renomear rota `/painel` → `/crm`, liberar `/` para `home#index`

**Files:**
- Modify: `config/routes.rb` (linhas 1-90, arquivo inteiro)

**Interfaces:**
- Consumes: nada (primeira task).
- Produces: rota nomeada `crm_path` (`GET /crm`) e `crm_session_path` (`GET /crm/session/:session_id`), disponíveis para todas as tasks seguintes. `root_path` passa a apontar para `home#index`.

- [ ] **Step 1: Reescrever `config/routes.rb`**

```ruby
require 'sidekiq/web'

Rails.application.routes.draw do
  root to: 'home#index'

  namespace :integrations do
    match 'shopify/events', to: 'shopify_events#create', via: [:post, :options]
  end

  scope '/crm' do
    devise_for :user, skip: [:registrations]

    authenticate :user do
      mount Sidekiq::Web => '/sidekiq'
    end

    resources :try_on, only: [:index, :create] do
      collection do
        get :status
      end
    end

    resources :clients
    resources :campaigns do
      resources :campaign_actions, only: [:index, :show], path: 'actions'
    end

    resources :events, only: [:index] do
      collection do
        get  'session/:session_id', action: :session_detail, as: :session
        post 'generate_link',       action: :generate_link,  as: :generate_link
      end
    end

    resources :affiliates

    post 'update_selected_client', to: 'clients#update_selected_client'
    get '/', to: 'dashboard#index', as: :crm
    get '/session/:session_id', to: 'dashboard#session_detail', as: :crm_session

    get '/shopify/auth', to: 'shopify_auth#auth'
    get '/shopify/callback', to: 'shopify_auth#callback'

    get    'clients/:id/google_ads/connect',    to: 'google_ads#connect',    as: :client_google_ads_connect
    get    'google_ads/callback',                to: 'google_ads#callback',   as: :google_ads_callback
    delete 'clients/:id/google_ads/disconnect', to: 'google_ads#disconnect', as: :client_google_ads_disconnect

    resources :dashboard, only: [:index]

    get  'vendas',               to: 'sales_dashboard#index',          as: :sales_dashboard
    post 'vendas/sync_ad_costs', to: 'sales_dashboard#sync_ad_costs', as: :sync_ad_costs_sales_dashboard

    resources :orders, only: [:index] do
      collection do
        get :export_xlsx
      end
      member do
        get :details
      end
    end

    resources :products, only: [:index] do
      collection do
        get :export_xlsx
      end
    end

    resources :customers, only: [:index] do
      collection do
        get :export_xlsx
      end
      member do
        get :details
      end
    end

    resources :users
    resources :profiles

    resources :attempts, only: [:index] do
      collection do
        get :verify_attempts
      end
    end
  end
end
```

- [ ] **Step 2: Verificar que as rotas foram geradas corretamente**

Run: `bin/rails routes | grep -E "^\s*crm "`
Expected: uma linha mostrando `crm GET /crm(.:format) dashboard#index` (e não mais `painel`).

- [ ] **Step 3: Commit**

```bash
git add config/routes.rb
git commit -m "feat: rename /painel to /crm, free root for institutional page"
```

---

### Task 2: Atualizar referências a `painel_path`/`painel_session_path` para `crm_path`/`crm_session_path`

**Files:**
- Modify: `app/controllers/try_on_controller.rb:46`
- Modify: `app/controllers/sales_dashboard_controller.rb:45`
- Modify: `app/views/layouts/partials/_footer.html.erb:18`
- Modify: `app/views/layouts/partials/_header.html.erb:12,29,88`
- Modify: `app/views/dashboard/index.html.erb:751,752,753,754,759,780,1146`

**Interfaces:**
- Consumes: `crm_path`, `crm_session_path` (Task 1).
- Produces: nenhuma referência a `painel_path`/`painel_session_path` restante no código.

- [ ] **Step 1: `app/controllers/try_on_controller.rb:46`**

```ruby
# antes
redirect_to painel_path, alert: 'Acesso negado. Apenas administradores podem acessar esta funcionalidade.'
# depois
redirect_to crm_path, alert: 'Acesso negado. Apenas administradores podem acessar esta funcionalidade.'
```

- [ ] **Step 2: `app/controllers/sales_dashboard_controller.rb:45`**

```ruby
# antes
redirect_to painel_path, alert: 'Dashboard de vendas não habilitado para este cliente.'
# depois
redirect_to crm_path, alert: 'Dashboard de vendas não habilitado para este cliente.'
```

- [ ] **Step 3: `app/views/layouts/partials/_footer.html.erb:18`**

```erb
<%# antes %>
<%= link_to painel_path, class: "crm-footer__link" do %>Dashboard<% end %>
<%# depois %>
<%= link_to crm_path, class: "crm-footer__link" do %>Dashboard<% end %>
```

- [ ] **Step 4: `app/views/layouts/partials/_header.html.erb` — 3 ocorrências**

Linha 12:
```erb
<%# antes %>
<%= link_to painel_path, class: "crm-header__brand" do %>
<%# depois %>
<%= link_to crm_path, class: "crm-header__brand" do %>
```

Linha 29:
```erb
<%# antes %>
<%= link_to painel_path, class: "crm-header__nav-link #{'active' if current_page?(painel_path)}" do %>
<%# depois %>
<%= link_to crm_path, class: "crm-header__nav-link #{'active' if current_page?(crm_path)}" do %>
```

Linha 88:
```erb
<%# antes %>
<%= link_to painel_path, class: "crm-header__dropdown-link" do %>
<%# depois %>
<%= link_to crm_path, class: "crm-header__dropdown-link" do %>
```

- [ ] **Step 5: `app/views/dashboard/index.html.erb` — 7 ocorrências (linhas 751-780, 1146)**

```erb
<%# antes (linhas 751-754) %>
<%= link_to "Hoje",    painel_path(period: "1"),  class: "db-filter-btn #{'db-filter-btn--active' if @period == '1' && !@using_month_filter}" %>
<%= link_to "7 dias",  painel_path(period: "7"),  class: "db-filter-btn #{'db-filter-btn--active' if @period == '7' && !@using_month_filter}" %>
<%= link_to "15 dias", painel_path(period: "15"), class: "db-filter-btn #{'db-filter-btn--active' if @period == '15' && !@using_month_filter}" %>
<%= link_to "30 dias", painel_path(period: "30"), class: "db-filter-btn #{'db-filter-btn--active' if @period == '30' && !@using_month_filter}" %>
<%# depois %>
<%= link_to "Hoje",    crm_path(period: "1"),  class: "db-filter-btn #{'db-filter-btn--active' if @period == '1' && !@using_month_filter}" %>
<%= link_to "7 dias",  crm_path(period: "7"),  class: "db-filter-btn #{'db-filter-btn--active' if @period == '7' && !@using_month_filter}" %>
<%= link_to "15 dias", crm_path(period: "15"), class: "db-filter-btn #{'db-filter-btn--active' if @period == '15' && !@using_month_filter}" %>
<%= link_to "30 dias", crm_path(period: "30"), class: "db-filter-btn #{'db-filter-btn--active' if @period == '30' && !@using_month_filter}" %>
```

```erb
<%# antes (linha 759) %>
<%= form_with url: painel_path, method: :get, local: true, class: "db-month-filter__form" do |f| %>
<%# depois %>
<%= form_with url: crm_path, method: :get, local: true, class: "db-month-filter__form" do |f| %>
```

```erb
<%# antes (linha 780) %>
<%= link_to painel_path(period: "1"), class: "db-month-filter__clear" do %>
<%# depois %>
<%= link_to crm_path(period: "1"), class: "db-month-filter__clear" do %>
```

```erb
<%# antes (linha 1146) %>
data-fetch-url="<%= painel_session_path(session_id: s[:session_id]) %>"
<%# depois %>
data-fetch-url="<%= crm_session_path(session_id: s[:session_id]) %>"
```

- [ ] **Step 6: Confirmar que nenhuma referência sobrou**

Run: `grep -rn "painel_path\|painel_session_path" app/`
Expected: nenhum resultado.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/try_on_controller.rb app/controllers/sales_dashboard_controller.rb \
  app/views/layouts/partials/_footer.html.erb app/views/layouts/partials/_header.html.erb \
  app/views/dashboard/index.html.erb
git commit -m "refactor: update painel_path/painel_session_path references to crm_path/crm_session_path"
```

---

### Task 3: Atualizar caminhos literais `/painel/...` para `/crm/...`

**Files:**
- Modify: `app/views/customers/index.html.erb:238`
- Modify: `app/views/layouts/partials/_footer.html.erb:32`
- Modify: `app/views/layouts/partials/_header.html.erb:121,184,691`

**Interfaces:**
- Consumes: nova rota `/crm/*` (Task 1).
- Produces: nenhum caminho literal `/painel/*` restante — necessário porque estes 5 usos não passam pelos route helpers (`painel_path`) que já foram cobertos na Task 2, e por isso não estavam no levantamento original de 13 referências do spec.

- [ ] **Step 1: `app/views/customers/index.html.erb:238`**

```js
// antes
fetch('/painel/customers/' + customerId + '/details', {
// depois
fetch('/crm/customers/' + customerId + '/details', {
```

- [ ] **Step 2: `app/views/layouts/partials/_footer.html.erb:32`**

```erb
<%# antes %>
<%= link_to "/painel/sidekiq", class: "crm-footer__link" do %>Sidekiq<% end %>
<%# depois %>
<%= link_to "/crm/sidekiq", class: "crm-footer__link" do %>Sidekiq<% end %>
```

- [ ] **Step 3: `app/views/layouts/partials/_header.html.erb` — 3 ocorrências**

Linha 121:
```erb
<%# antes %>
<%= link_to '/painel/sidekiq', class: "crm-header__dropdown-link", target: '_blank' do %>
<%# depois %>
<%= link_to '/crm/sidekiq', class: "crm-header__dropdown-link", target: '_blank' do %>
```

Linha 184:
```erb
<%# antes %>
<%= link_to '/painel/sidekiq', class: 'crm-header__dropdown-item', target: '_blank' do %>
<%# depois %>
<%= link_to '/crm/sidekiq', class: 'crm-header__dropdown-item', target: '_blank' do %>
```

Linha 691 (dentro do `<script>`):
```js
// antes
fetch('/painel/update_selected_client', {
// depois
fetch('/crm/update_selected_client', {
```

- [ ] **Step 4: Confirmar que nenhum caminho literal sobrou**

Run: `grep -rn "'/painel\|\"/painel" app/`
Expected: nenhum resultado.

- [ ] **Step 5: Commit**

```bash
git add app/views/customers/index.html.erb app/views/layouts/partials/_footer.html.erb \
  app/views/layouts/partials/_header.html.erb
git commit -m "refactor: update hardcoded /painel/* paths to /crm/*"
```

---

### Task 4: Corrigir redirects de `root_path` que devem continuar apontando para o CRM (não para a página institucional)

**Files:**
- Modify: `app/controllers/application_controller.rb:15`
- Modify: `app/controllers/campaigns_controller.rb:86`
- Modify: `app/controllers/affiliates_controller.rb:84`
- Modify: `test/controllers/sales_dashboard_controller_test.rb:25,95`

**Interfaces:**
- Consumes: `crm_path` (Task 1).
- Produces: usuários autenticados que batem em uma checagem de autorização (não-admin, sem cliente vinculado) continuam voltando para dentro do `/crm`, em vez de serem jogados para a página institucional pública. Isso não está no spec original — é uma consequência do `root_path` mudar de significado (antes `redirect('/painel')`, agora `home#index`) que só fica visível ao mapear todos os usos de `root_path` no código.

- [ ] **Step 1: `app/controllers/application_controller.rb:15`**

```ruby
# antes
def require_admin!
  unless current_user&.admin?
    redirect_to root_path, alert: 'Acesso restrito a administradores.'
  end
end
# depois
def require_admin!
  unless current_user&.admin?
    redirect_to crm_path, alert: 'Acesso restrito a administradores.'
  end
end
```

- [ ] **Step 2: `app/controllers/campaigns_controller.rb:86`**

```ruby
# antes
def require_client!
  unless current_client.present?
    redirect_to root_path, alert: 'Você precisa estar vinculado a um cliente para acessar campanhas.'
  end
end
# depois
def require_client!
  unless current_client.present?
    redirect_to crm_path, alert: 'Você precisa estar vinculado a um cliente para acessar campanhas.'
  end
end
```

- [ ] **Step 3: `app/controllers/affiliates_controller.rb:84`**

```ruby
# antes
def require_client!
  unless current_client.present?
    redirect_to root_path, alert: 'Você precisa estar vinculado a um cliente para acessar afiliados.'
  end
end
# depois
def require_client!
  unless current_client.present?
    redirect_to crm_path, alert: 'Você precisa estar vinculado a um cliente para acessar afiliados.'
  end
end
```

- [ ] **Step 4: Atualizar o teste que verifica o redirect de `require_admin!`**

`test/controllers/sales_dashboard_controller_test.rb:95` testa exatamente o `require_admin!` alterado no Step 1 (via `sync_ad_costs`). `test/controllers/sales_dashboard_controller_test.rb:25` testa `ensure_dashboard_access!`, que já usa `painel_path` (corrigido para `crm_path` na Task 2) — como é a mesma classe `SalesDashboardController`, o método já foi renomeado; o teste também precisa acompanhar.

```ruby
# antes (linha 25)
assert_redirected_to painel_path
# depois
assert_redirected_to crm_path
```

```ruby
# antes (linha 95)
assert_redirected_to root_path
# depois
assert_redirected_to crm_path
```

- [ ] **Step 5: Rodar a suíte de testes**

Run: `bin/rails test test/controllers/sales_dashboard_controller_test.rb`
Expected: `8 runs, ..., 0 failures, 0 errors`.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/application_controller.rb app/controllers/campaigns_controller.rb \
  app/controllers/affiliates_controller.rb test/controllers/sales_dashboard_controller_test.rb
git commit -m "fix: keep authorization redirects inside /crm instead of the public root"
```

---

### Task 5: `HomeController` renderiza a página institucional para qualquer visitante

**Files:**
- Modify: `app/controllers/home_controller.rb` (arquivo inteiro, 5 linhas)
- Modify: `app/controllers/application_controller.rb:20-32` (`redirect_affiliate_to_events!`)

**Interfaces:**
- Consumes: `root to: 'home#index'` (Task 1).
- Produces: `GET /` renderiza `home/index` (Task 13) para visitantes autenticados e não autenticados, sem redirect condicional. Necessário também impedir dois `before_action`s globais de `ApplicationController` de interferir: `authenticate_user!` (forçaria login) e `redirect_affiliate_to_events!` (jogaria um afiliado logado para `events_path` em vez de mostrar a página institucional) — nenhum dos dois está mencionado no spec, mas ambos quebram o requisito "renderiza pra qualquer visitante (autenticado ou não)" se não forem tratados.

- [ ] **Step 1: Reescrever `app/controllers/home_controller.rb`**

```ruby
class HomeController < ApplicationController
  skip_before_action :authenticate_user!, only: [:index]

  def index; end
end
```

- [ ] **Step 2: Impedir que `redirect_affiliate_to_events!` capture a home pública**

```ruby
# app/controllers/application_controller.rb:20-32, antes
def redirect_affiliate_to_events!
  return unless user_signed_in?

  return unless current_user.profile_id == Profile::AFFILIATE

  # NÃO roda para Devise (login, logout, etc)
  return if devise_controller?

  # Permite events
  return if controller_name == 'events'

  redirect_to events_path(utm_code: current_user.utm_code)
end
```

```ruby
# depois
def redirect_affiliate_to_events!
  return unless user_signed_in?

  return unless current_user.profile_id == Profile::AFFILIATE

  # NÃO roda para Devise (login, logout, etc)
  return if devise_controller?

  # Permite events e a página institucional pública
  return if controller_name == 'events'
  return if controller_name == 'home'

  redirect_to events_path(utm_code: current_user.utm_code)
end
```

- [ ] **Step 3: Rodar a suíte completa para garantir que nada quebrou**

Run: `bin/rails test`
Expected: `41 runs, ..., 0 failures, 0 errors` (mesmo baseline de antes das mudanças de rota).

- [ ] **Step 4: Commit**

```bash
git add app/controllers/home_controller.rb app/controllers/application_controller.rb
git commit -m "feat: render institutional page for any visitor at root"
```

---

### Task 6: Tokens de design (`tokens.scss`) + fonte

**Files:**
- Create: `app/assets/stylesheets/tokens.scss`
- Modify: `app/assets/stylesheets/admin.scss:1-24` (adicionar `require tokens` depois de `require layouts/global`)
- Modify: `app/views/layouts/application.html.erb:1-25` (adicionar link da fonte + script anti-flash de tema)

**Interfaces:**
- Consumes: nada de tasks anteriores (arquivo novo).
- Produces: custom properties `--primary`, `--bg`, `--fg`, `--fg-alt`, `--chrome-bg`, `--chrome-fg`, `--outline`, `--primary-tint`, `--radius` em `:root` (claro) e `:root.theme-dark` (escuro) — consumidas por todas as tasks de CSS seguintes (7-12).

- [ ] **Step 1: Criar `app/assets/stylesheets/tokens.scss`**

```scss
:root {
  --primary: #1967d2;
  --bg: #ffffff;
  --fg: #212121;
  --fg-alt: #6a6f71;
  --chrome-bg: #1c2834;
  --chrome-fg: #F3F4F6;
  --outline: #e7e8ed;
  --primary-tint: rgba(25, 103, 210, .08);
  --radius: 0.45rem;
}

:root.theme-dark {
  --primary: #47b0f8;
  --bg: #121317;
  --fg: #dcdcdc;
  --fg-alt: #a8acad;
  --chrome-bg: #0c1116;
  --chrome-fg: #F3F4F6;
  --outline: #2c313a;
  --primary-tint: rgba(71, 176, 248, .12);
}

body {
  font-family: 'Google Sans Flex', 'Roboto', ui-sans-serif, sans-serif;
  background: var(--bg);
  color: var(--fg);
}
```

- [ ] **Step 2: Adicionar `require tokens` em `app/assets/stylesheets/admin.scss`**

```scss
# antes (linhas 13-23)
 *= require bootstrap
 *= require datatables/media/css/jquery.dataTables.min.css
 *= require layouts/global
 *= require layouts/wrapper
 *= require layouts/utils
 *= require layouts/header
 *= require layouts/chosen
 *= require layouts/products
 *= require layouts/orders
 *= require layouts/customers
 *= require_self
 */
```

```scss
# depois
 *= require bootstrap
 *= require datatables/media/css/jquery.dataTables.min.css
 *= require layouts/global
 *= require tokens
 *= require layouts/wrapper
 *= require layouts/utils
 *= require layouts/header
 *= require layouts/chosen
 *= require layouts/products
 *= require layouts/orders
 *= require layouts/customers
 *= require_self
 */
```

`tokens` entra depois de `layouts/global` de propósito: `global.scss` define `body { font-family: "Google Sans","Roboto", sans-serif; color: #1c599a; }` — como as duas regras têm a mesma especificidade, a que carrega depois vence a cascata, garantindo que a fonte/cor nova prevaleça sem precisar tocar em `global.scss` agora.

- [ ] **Step 3: Carregar a fonte e o script anti-flash de tema em `app/views/layouts/application.html.erb`**

```erb
<%# antes (linhas 1-25) %>
<!DOCTYPE html>
<html>
  <head>
    <title><%= content_for?(:title) ? "#{yield(:title)} - Mewtda - Painel" : 'Mewtda - Painel' %></title>
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <meta name="turbo-cache-control" content="no-cache">
    <meta name="turbolinks-visit-control" content="reload">
    
    <%= csrf_meta_tags %>
    <%= csp_meta_tag %>
    <%= stylesheet_link_tag 'admin', media: 'all', 'data-turbo-track': 'reload'  %>
    <%= javascript_include_tag "application", 'data-turbo-track': 'reload' %>

    <script
      src="https://cdn.jsdelivr.net/npm/@popperjs/core@2.10.2/dist/umd/popper.min.js"
      integrity="sha384-7+zCNj/IqJ95wo16oMtfsKbZ9ccEh31eOz1HGyDuCQ6wgnyJNSYdrPa03rtR1zdB"
      crossorigin="anonymous"
    ></script>

    <script
      src="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/js/bootstrap.min.js"
      integrity="sha384-QJHtvGhmr9XOIpI6YVutG+2QOK9T+ZnN4kzFN1RtK3zEFEIsxhlmWl5/YESvpZ13"
      crossorigin="anonymous"
    ></script>
  </head>
```

```erb
<%# depois %>
<!DOCTYPE html>
<html>
  <head>
    <title><%= content_for?(:title) ? "#{yield(:title)} - Mewtda" : 'Mewtda' %></title>
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <meta name="turbo-cache-control" content="no-cache">
    <meta name="turbolinks-visit-control" content="reload">

    <script>
      (function () {
        if (localStorage.getItem('crm-theme') === 'dark') {
          document.documentElement.classList.add('theme-dark');
        }
      })();
    </script>

    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link href="https://fonts.googleapis.com/css2?family=Google+Sans+Flex:opsz,wght@6..72,400..700&display=swap" rel="stylesheet">

    <%= csrf_meta_tags %>
    <%= csp_meta_tag %>
    <%= stylesheet_link_tag 'admin', media: 'all', 'data-turbo-track': 'reload'  %>
    <%= javascript_include_tag "application", 'data-turbo-track': 'reload' %>

    <script
      src="https://cdn.jsdelivr.net/npm/@popperjs/core@2.10.2/dist/umd/popper.min.js"
      integrity="sha384-7+zCNj/IqJ95wo16oMtfsKbZ9ccEh31eOz1HGyDuCQ6wgnyJNSYdrPa03rtR1zdB"
      crossorigin="anonymous"
    ></script>

    <script
      src="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/js/bootstrap.min.js"
      integrity="sha384-QJHtvGhmr9XOIpI6YVutG+2QOK9T+ZnN4kzFN1RtK3zEFEIsxhlmWl5/YESvpZ13"
      crossorigin="anonymous"
    ></script>
  </head>
```

O script de tema fica no `<head>`, antes de qualquer CSS, e aplica a classe em `document.documentElement` (`<html>`) — não em `<body>` — porque o `<html>` já existe nesse ponto do parsing, evitando o flash de tela clara antes do CSS carregar.

- [ ] **Step 4: Verificar visualmente**

Run: `bin/rails server` (ou o comando de dev já usado no projeto) e abrir `http://localhost:3000/crm` logado.
Expected: fonte `Google Sans Flex` aplicada no texto do body; nenhuma quebra visual grosseira (o resto ainda está com o CSS antigo, isso é esperado até as próximas tasks).

- [ ] **Step 5: Commit**

```bash
git add app/assets/stylesheets/tokens.scss app/assets/stylesheets/admin.scss app/views/layouts/application.html.erb
git commit -m "feat: add design tokens (light/dark) and load Google Sans Flex"
```

---

### Task 7: Botão de alternância de tema (JS + wiring)

**Files:**
- Modify: `app/assets/stylesheets/tokens.scss` (adicionar regras do ícone sol/lua)
- Modify: `app/views/layouts/partials/_header.html.erb` (adicionar botão + função JS `toggleTheme`)

**Interfaces:**
- Consumes: classe `.theme-dark` em `<html>` e script anti-flash (Task 6).
- Produces: função global `toggleTheme()` e botão `.crm-theme-toggle` reutilizável — nenhuma outra task depende diretamente disso, mas é o mecanismo de alternância que valida visualmente todas as tasks de CSS seguintes.

- [ ] **Step 1: Adicionar estilos do ícone sol/lua em `tokens.scss`**

```scss
# adicionar ao final de app/assets/stylesheets/tokens.scss
.crm-theme-toggle {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 36px;
  height: 36px;
  border-radius: 50%;
  border: none;
  background: transparent;
  color: var(--chrome-fg);
  cursor: pointer;
  transition: background .15s;
}

.crm-theme-toggle:hover {
  background: rgba(255, 255, 255, 0.1);
}

.crm-theme-toggle .fa-sun { display: none; }
.crm-theme-toggle .fa-moon { display: block; }

:root.theme-dark .crm-theme-toggle .fa-sun { display: block; }
:root.theme-dark .crm-theme-toggle .fa-moon { display: none; }
```

- [ ] **Step 2: Adicionar o botão no header, ao lado do menu do usuário**

No `app/views/layouts/partials/_header.html.erb`, dentro de `.crm-header__actions` (linha 137), antes do `<div class="crm-header__user" ...>` (linha 151):

```erb
<%# antes %>
  <div class="crm-header__actions">

    <% if current_user.admin? %>
      <select class="crm-header__client-select" onchange="updateSelectedClient(this.value)">
<%# depois %>
  <div class="crm-header__actions">

    <button type="button" class="crm-theme-toggle" onclick="toggleTheme()" aria-label="Alternar tema">
      <i class="fa-solid fa-sun"></i>
      <i class="fa-solid fa-moon"></i>
    </button>

    <% if current_user.admin? %>
      <select class="crm-header__client-select" onchange="updateSelectedClient(this.value)">
```

- [ ] **Step 3: Adicionar `toggleTheme()` ao `<script>` do header**

No mesmo arquivo, dentro do bloco `<script>` (perto de `updateSelectedClient`, linha 687):

```js
// adicionar antes de `function updateSelectedClient(clientId) {`
function toggleTheme() {
  var isDark = document.documentElement.classList.toggle('theme-dark');
  localStorage.setItem('crm-theme', isDark ? 'dark' : 'light');
}
```

- [ ] **Step 4: Verificar visualmente**

Abrir `/crm` logado, clicar no botão de tema: o ícone deve trocar de lua para sol e as variáveis `--bg`/`--fg` devem mudar (visível no `<body>`, mesmo que o resto da tela ainda não tenha adotado os tokens). Recarregar a página: o tema escolhido deve persistir (via `localStorage`).

- [ ] **Step 5: Commit**

```bash
git add app/assets/stylesheets/tokens.scss app/views/layouts/partials/_header.html.erb
git commit -m "feat: add light/dark theme toggle button"
```

---

### Task 8: Componentes base (botão, input, tabela, card, tag)

**Files:**
- Create: `app/assets/stylesheets/components/_button.scss`
- Create: `app/assets/stylesheets/components/_input.scss`
- Create: `app/assets/stylesheets/components/_table.scss`
- Create: `app/assets/stylesheets/components/_card.scss`
- Create: `app/assets/stylesheets/components/_tag.scss`
- Modify: `app/assets/stylesheets/admin.scss` (adicionar os 5 requires)

**Interfaces:**
- Consumes: tokens (`--primary`, `--bg`, `--fg`, `--fg-alt`, `--outline`, `--primary-tint`, `--radius`) de `tokens.scss` (Task 6).
- Produces: classes `.crm-btn`/`.crm-btn--primary`/`.crm-btn--secondary`, `.crm-input`/`.crm-label`, `.crm-table`, `.crm-card`/`.crm-kpi-card`/`.crm-kpi-card__label`/`.crm-kpi-card__value`, `.crm-tag`/`.crm-tag--success`/`.crm-tag--danger`/`.crm-tag--warning`/`.crm-tag--neutral`/`.crm-tag--info` — usadas pela Task 12 (página institucional) e por todas as tasks de migração visual de view (16-50).

- [ ] **Step 1: Criar `app/assets/stylesheets/components/_button.scss`**

```scss
.crm-btn {
  display: inline-flex;
  align-items: center;
  gap: 0.4rem;
  font-family: inherit;
  font-size: 0.875rem;
  font-weight: 600;
  padding: 0.55rem 1.1rem;
  border-radius: var(--radius);
  border: 1px solid transparent;
  cursor: pointer;
  transition: background .15s, color .15s, border-color .15s, filter .15s;
  text-decoration: none;
}

.crm-btn--primary {
  background: var(--primary);
  color: #fff;
}

.crm-btn--primary:hover {
  filter: brightness(0.92);
}

.crm-btn--secondary {
  background: transparent;
  border-color: var(--outline);
  color: var(--fg);
}

.crm-btn--secondary:hover {
  background: var(--primary-tint);
  border-color: var(--primary);
  color: var(--primary);
}
```

- [ ] **Step 2: Criar `app/assets/stylesheets/components/_input.scss`**

```scss
.crm-input {
  width: 100%;
  font-family: inherit;
  font-size: 0.875rem;
  color: var(--fg);
  background: var(--bg);
  border: 1px solid var(--outline);
  border-radius: var(--radius);
  padding: 0.55rem 0.75rem;
  transition: border-color .15s, box-shadow .15s;
}

.crm-input:focus {
  outline: none;
  border-color: var(--primary);
  box-shadow: 0 0 0 3px var(--primary-tint);
}

.crm-label {
  display: block;
  font-size: 0.8125rem;
  font-weight: 600;
  color: var(--fg-alt);
  margin-bottom: 0.35rem;
}
```

- [ ] **Step 3: Criar `app/assets/stylesheets/components/_table.scss`**

```scss
.crm-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 0.875rem;
  color: var(--fg);
}

.crm-table th {
  text-align: left;
  font-size: 0.75rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: .04em;
  color: var(--fg-alt);
  padding: 0.75rem 1rem;
  border-bottom: 1px solid var(--outline);
}

.crm-table td {
  padding: 0.75rem 1rem;
  border-bottom: 1px solid var(--outline);
}

.crm-table tbody tr:hover {
  background: var(--primary-tint);
}
```

- [ ] **Step 4: Criar `app/assets/stylesheets/components/_card.scss`**

```scss
.crm-card {
  background: var(--bg);
  border: 1px solid var(--outline);
  border-radius: var(--radius);
  padding: 1.25rem;
}

.crm-kpi-card {
  background: var(--bg);
  border: 1px solid var(--outline);
  border-radius: var(--radius);
  padding: 1rem 1.25rem;
}

.crm-kpi-card__label {
  font-size: 0.75rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: .04em;
  color: var(--fg-alt);
}

.crm-kpi-card__value {
  font-size: 1.5rem;
  font-weight: 700;
  color: var(--fg);
  margin-top: 0.25rem;
}
```

- [ ] **Step 5: Criar `app/assets/stylesheets/components/_tag.scss`**

```scss
.crm-tag {
  display: inline-flex;
  align-items: center;
  font-size: 0.75rem;
  font-weight: 600;
  padding: 0.2rem 0.6rem;
  border-radius: 999px;
}

.crm-tag--success { background: #e6f4ea; color: #1d7a3e; }
.crm-tag--danger  { background: #fce8e6; color: #c5221f; }
.crm-tag--warning { background: #fef7e0; color: #b06000; }
.crm-tag--neutral { background: var(--outline); color: var(--fg-alt); }
.crm-tag--info    { background: var(--primary-tint); color: var(--primary); }
```

- [ ] **Step 6: Adicionar os requires em `app/assets/stylesheets/admin.scss`**

```scss
# antes (trecho de requires, já modificado na Task 6)
 *= require layouts/customers
 *= require_self
 */
```

```scss
# depois
 *= require layouts/customers
 *= require components/button
 *= require components/input
 *= require components/table
 *= require components/card
 *= require components/tag
 *= require_self
 */
```

- [ ] **Step 7: Verificar que o asset compila sem erro**

Run: `bin/rails assets:precompile RAILS_ENV=test 2>&1 | tail -20` (ou apenas recarregar uma página no navegador em dev e checar o console/log do servidor por erro de Sprockets).
Expected: nenhum erro de compilação SCSS.

- [ ] **Step 8: Commit**

```bash
git add app/assets/stylesheets/components/ app/assets/stylesheets/admin.scss
git commit -m "feat: add base component styles (button, input, table, card, tag)"
```

---

### Task 9: Topbar — extrair CSS inline do header para `layouts/topbar.scss`, remover navegação (vai para a sidebar)

**Files:**
- Create: `app/assets/stylesheets/layouts/topbar.scss`
- Modify: `app/views/layouts/partials/_header.html.erb` (arquivo inteiro — remove `<nav>` com os grupos, remove `<style>` inline, mantém hamburger/brand/actions/script)
- Modify: `app/assets/stylesheets/admin.scss` (troca `require layouts/header` por `require layouts/topbar`)

**Interfaces:**
- Consumes: tokens (Task 6), botão de tema já embutido no header (Task 7).
- Produces: elemento `#crm-hamburger` que a Task 10 (sidebar) passa a escutar como trigger do drawer mobile (em vez de abrir `#crm-nav`, que deixa de existir).

- [ ] **Step 1: Criar `app/assets/stylesheets/layouts/topbar.scss` com o CSS que hoje está inline em `_header.html.erb`, reescrito com os tokens**

```scss
.crm-fa {
  margin-right: 6px;
  color: var(--fg-alt);
  font-size: 13px;
}

.crm-header {
  height: 64px;
  background: var(--chrome-bg);
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0 20px;
  position: sticky;
  top: 0;
  z-index: 200;
}

.crm-header__left {
  display: flex;
  align-items: center;
  gap: 15px;
}

.crm-header__logo {
  width: 140px;
}

.crm-header__actions {
  display: flex;
  align-items: center;
  gap: 12px;
}

.crm-header__client-select {
  height: 36px;
  border-radius: var(--radius);
  border: 1px solid rgba(255, 255, 255, 0.2);
  padding: 0 10px;
  font-size: 13px;
  color: var(--chrome-fg);
  background: rgba(255, 255, 255, 0.08);
  cursor: pointer;
  outline: none;
  transition: border-color 0.15s;
}

.crm-header__client-select:focus {
  border-color: var(--primary);
}

.crm-header__user {
  position: relative;
  cursor: pointer;
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 4px 8px 4px 4px;
  border-radius: 40px;
  transition: background 0.15s;
}

.crm-header__user:hover {
  background: rgba(255, 255, 255, 0.08);
}

.crm-header__avatar {
  width: 34px;
  height: 34px;
  border-radius: 50%;
  background: var(--primary);
  color: #fff;
  display: flex;
  align-items: center;
  justify-content: center;
  font-weight: 700;
  font-size: 14px;
  flex-shrink: 0;
}

.crm-user-chevron {
  font-size: 11px;
  color: var(--chrome-fg);
  transition: transform 0.2s ease;
}

.crm-user-chevron.open {
  transform: rotate(180deg);
}

.crm-header__dropdown {
  position: absolute;
  right: 0;
  top: calc(100% + 8px);
  width: 210px;
  background: var(--bg);
  border: 1px solid var(--outline);
  border-radius: 12px;
  box-shadow: 0 8px 24px rgba(0,0,0,0.2);
  display: none;
  padding: 6px;
  z-index: 300;
}

.crm-header__dropdown.open {
  display: block;
}

.crm-header__dropdown-header {
  padding: 10px 12px 12px;
  font-size: 13px;
  color: var(--fg-alt);
}

.crm-header__dropdown-header strong {
  font-size: 14px;
  color: var(--fg);
  display: block;
  margin-bottom: 2px;
}

.crm-header__dropdown-sep {
  height: 1px;
  background: var(--outline);
  margin: 4px 0;
}

.crm-header__dropdown-item {
  display: flex;
  align-items: center;
  padding: 9px 12px;
  text-decoration: none;
  color: var(--fg);
  font-size: 14px;
  border-radius: 8px;
  transition: background 0.12s, color 0.12s;
}

.crm-header__dropdown-item:hover {
  background: var(--primary-tint);
  color: var(--primary);
}

.crm-header__dropdown-item:hover .crm-fa {
  color: var(--primary);
}

.crm-header__dropdown-item--danger {
  color: #e74c3c !important;
}

.crm-header__dropdown-item--danger:hover {
  background: rgba(231, 76, 60, 0.1) !important;
  color: #c0392b !important;
}

.crm-header__dropdown-item--danger .crm-fa {
  color: #e74c3c !important;
}

.crm-header__hamburger {
  display: none;
  flex-direction: column;
  justify-content: center;
  align-items: center;
  gap: 5px;
  width: 38px;
  height: 38px;
  background: none;
  border: none;
  border-radius: 8px;
  cursor: pointer;
  padding: 0;
  transition: background 0.15s;
}

.crm-header__hamburger:hover {
  background: rgba(255, 255, 255, 0.1);
}

.crm-hamburger__bar {
  display: block;
  width: 20px;
  height: 2px;
  background: var(--chrome-fg);
  border-radius: 2px;
  transition: transform 0.25s ease, opacity 0.2s ease, width 0.2s ease;
  transform-origin: center;
}

.crm-header__hamburger.open .crm-hamburger__bar:nth-child(1) {
  transform: translateY(7px) rotate(45deg);
}
.crm-header__hamburger.open .crm-hamburger__bar:nth-child(2) {
  opacity: 0;
  width: 0;
}
.crm-header__hamburger.open .crm-hamburger__bar:nth-child(3) {
  transform: translateY(-7px) rotate(-45deg);
}

.crm-nav-overlay {
  display: none;
  position: fixed;
  inset: 0;
  background: rgba(0,0,0,0.4);
  z-index: 150;
}

.crm-nav-overlay.open {
  display: block;
}

@media (max-width: 768px) {
  .crm-header__hamburger {
    display: flex;
  }

  .crm-header__client-select {
    display: none;
  }
}
```

- [ ] **Step 2: Reescrever `app/views/layouts/partials/_header.html.erb` sem o `<nav>` de grupos e sem `<style>` inline**

```erb
<header class="crm-header">

  <!-- LEFT -->
  <div class="crm-header__left">

    <button class="crm-header__hamburger" id="crm-hamburger" type="button" aria-label="Abrir menu" aria-expanded="false">
      <span class="crm-hamburger__bar"></span>
      <span class="crm-hamburger__bar"></span>
      <span class="crm-hamburger__bar"></span>
    </button>

    <%= link_to crm_path, class: "crm-header__brand" do %>
      <%= image_tag 'admin/logo-novo.png', class: 'crm-header__logo' %>
    <% end %>

  </div>

  <!-- RIGHT -->
  <div class="crm-header__actions">

    <button type="button" class="crm-theme-toggle" onclick="toggleTheme()" aria-label="Alternar tema">
      <i class="fa-solid fa-sun"></i>
      <i class="fa-solid fa-moon"></i>
    </button>

    <% if current_user.admin? %>
      <select class="crm-header__client-select" onchange="updateSelectedClient(this.value)">
        <option value="">Cliente</option>
        <% Client.where(active: true).order(:name).each do |client| %>
          <option value="<%= client.id %>" <%= "selected" if session[:selected_client_id].to_i == client.id %>>
            <%= client.name %>
          </option>
        <% end %>
      </select>
    <% end %>

    <!-- USER -->
    <div class="crm-header__user" id="crm-user-menu">

      <div class="crm-header__avatar">
        <%= current_user.name.first.upcase %>
      </div>

      <i class="fa-solid fa-chevron-down crm-user-chevron"></i>

      <div class="crm-header__dropdown" id="crm-dropdown">

        <div class="crm-header__dropdown-header">
          <strong><%= current_user.name %></strong><br>
          <span><%= current_user.admin? ? 'Administrador' : 'Usuário' %></span>
        </div>

        <div class="crm-header__dropdown-sep"></div>

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

          <%= link_to '/crm/sidekiq', class: 'crm-header__dropdown-item', target: '_blank' do %>
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
        <% end %>

        <%= link_to destroy_user_session_path,
          data: { turbo: false },
          class: 'crm-header__dropdown-item crm-header__dropdown-item--danger' do %>
          <i class="fa-solid fa-right-from-bracket crm-fa"></i>
          Sair
        <% end %>

      </div>

    </div>

  </div>

</header>

<!-- MOBILE OVERLAY -->
<div class="crm-nav-overlay" id="crm-nav-overlay"></div>

<script>

/* CLIENT */
function updateSelectedClient(clientId) {
  if (!clientId) return;

  fetch('/crm/update_selected_client', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
    },
    body: JSON.stringify({ client_id: clientId })
  })
  .then(() => location.reload());
}

function toggleTheme() {
  var isDark = document.documentElement.classList.toggle('theme-dark');
  localStorage.setItem('crm-theme', isDark ? 'dark' : 'light');
}

(function () {

  /* USER DROPDOWN */
  const menu     = document.getElementById('crm-user-menu');
  const dropdown = document.getElementById('crm-dropdown');
  const chevron  = menu ? menu.querySelector('.crm-user-chevron') : null;

  function closeUserDropdown() {
    if (!dropdown) return;
    dropdown.classList.remove('open');
    if (chevron) chevron.classList.remove('open');
  }

  function openUserDropdown() {
    if (!dropdown) return;
    dropdown.classList.add('open');
    if (chevron) chevron.classList.add('open');
  }

  if (menu) {
    menu.addEventListener('click', function (e) {
      e.stopPropagation();
      const isOpen = dropdown.classList.contains('open');
      isOpen ? closeUserDropdown() : openUserDropdown();
    });

    document.addEventListener('click', function () {
      closeUserDropdown();
    });

    dropdown.addEventListener('click', function (e) {
      e.stopPropagation();
    });
  }

  /* HAMBURGER — abre a sidebar (drawer mobile), ver layouts/partials/_sidebar */
  const hamburger = document.getElementById('crm-hamburger');
  const sidebar   = document.getElementById('crm-sidebar');
  const overlay   = document.getElementById('crm-nav-overlay');

  function openSidebar() {
    sidebar.classList.add('open');
    hamburger.classList.add('open');
    overlay.classList.add('open');
    hamburger.setAttribute('aria-expanded', 'true');
    document.body.style.overflow = 'hidden';
  }

  function closeSidebar() {
    sidebar.classList.remove('open');
    hamburger.classList.remove('open');
    overlay.classList.remove('open');
    hamburger.setAttribute('aria-expanded', 'false');
    document.body.style.overflow = '';
  }

  if (hamburger && sidebar) {
    hamburger.addEventListener('click', function () {
      sidebar.classList.contains('open') ? closeSidebar() : openSidebar();
    });
  }

  if (overlay) {
    overlay.addEventListener('click', closeSidebar);
  }

})();

</script>
```

Nota: o `id="crm-nav-overlay"` continua no header (compartilhado entre topbar e sidebar), e o `id="crm-sidebar"` referenciado no script acima é criado na Task 10.

- [ ] **Step 3: Trocar o require em `app/assets/stylesheets/admin.scss`**

```scss
# antes
 *= require layouts/header
```

```scss
# depois
 *= require layouts/topbar
```

- [ ] **Step 4: Verificar visualmente**

Abrir `/crm` logado em desktop: topbar escura fixa no topo, sem itens de navegação horizontal (esperado — a navegação ainda não existe até a Task 10, então o site fica temporariamente sem menu; isso é aceitável como estado intermediário do plano). Abrir o dropdown do usuário e o seletor de cliente (se admin) para confirmar que ainda funcionam.

- [ ] **Step 5: Commit**

```bash
git add app/assets/stylesheets/layouts/topbar.scss app/views/layouts/partials/_header.html.erb app/assets/stylesheets/admin.scss
git rm app/assets/stylesheets/layouts/header.scss
git commit -m "refactor: extract topbar styles to tokens-based topbar.scss, drop inline nav"
```

---

### Task 10: Sidebar — nova navegação vertical fixa (reaproveita `_sidebar.html.erb`, hoje órfão)

**Files:**
- Modify: `app/views/layouts/partials/_sidebar.html.erb` (arquivo inteiro — hoje é uma sidebar não utilizada em lugar nenhum, com itens "Leads"/"Relatórios" que não existem mais no roteamento; reescrita completa)
- Modify: `app/assets/stylesheets/layouts/sidebar.scss` (arquivo inteiro — reescrito com tokens)
- Modify: `app/views/layouts/application.html.erb` (renderizar a sidebar dentro de um wrapper flex)
- Modify: `app/views/layouts/partials/_content.html.erb` (ajustar para conviver com a sidebar fixa)

**Interfaces:**
- Consumes: `#crm-hamburger` e `#crm-nav-overlay` (Task 9), classes `.crm-fa` (Task 9).
- Produces: `#crm-sidebar` (consumido pelo script da Task 9 para abrir/fechar em mobile), classe `.crm-shell__body` que define o layout flex topbar+sidebar+conteúdo.

- [ ] **Step 1: Reescrever `app/views/layouts/partials/_sidebar.html.erb` com os mesmos grupos/itens que existiam no `<nav>` antigo do header, verticalizados**

```erb
<aside class="crm-sidebar" id="crm-sidebar">
  <nav class="crm-sidebar__nav">

    <% if current_user.profile_id == Profile::AFFILIATE %>
      <!-- AFILIADO: apenas seus eventos -->
      <%= link_to events_path(utm_code: current_user.utm_code), class: "crm-sidebar__link #{'active' if request.path.start_with?(events_path)}" do %>
        <i class="fa-solid fa-chart-line crm-fa"></i>
        Meus Eventos
      <% end %>
    <% else %>
      <%= link_to crm_path, class: "crm-sidebar__link #{'active' if current_page?(crm_path)}" do %>
        <i class="fa-solid fa-chart-line crm-fa"></i>
        Dashboard
      <% end %>

      <% if current_user.admin? || current_user.client&.sales_dashboard_enabled? %>
        <%= link_to sales_dashboard_path, class: "crm-sidebar__link #{'active' if current_page?(sales_dashboard_path)}" do %>
          <i class="fa-solid fa-sack-dollar crm-fa"></i>
          Vendas
        <% end %>
      <% end %>

      <div class="crm-sidebar__group">
        <span class="crm-sidebar__group-label">Operações</span>

        <%= link_to orders_path, class: "crm-sidebar__link #{'active' if current_page?(orders_path)}" do %>
          <i class="fa-solid fa-box crm-fa"></i>
          Pedidos
        <% end %>

        <%= link_to customers_path, class: "crm-sidebar__link #{'active' if current_page?(customers_path)}" do %>
          <i class="fa-solid fa-users crm-fa"></i>
          Clientes
        <% end %>

        <%= link_to products_path, class: "crm-sidebar__link #{'active' if current_page?(products_path)}" do %>
          <i class="fa-solid fa-bag-shopping crm-fa"></i>
          Produtos
        <% end %>
      </div>
    <% end %>

    <% unless current_user.profile_id == Profile::AFFILIATE %>
      <div class="crm-sidebar__group">
        <span class="crm-sidebar__group-label">Marketing</span>

        <%= link_to campaigns_path, class: "crm-sidebar__link #{'active' if request.path.start_with?(campaigns_path)}" do %>
          <i class="fa-solid fa-bullseye crm-fa"></i>
          Campanhas
        <% end %>

        <%= link_to affiliates_path, class: "crm-sidebar__link #{'active' if request.path.start_with?(affiliates_path)}" do %>
          <i class="fa-solid fa-user-group crm-fa"></i>
          Afiliados
        <% end %>

        <%= link_to crm_path, class: "crm-sidebar__link" do %>
          <i class="fa-solid fa-robot crm-fa"></i>
          Automações
        <% end %>
      </div>
    <% end %>

    <% if current_user.admin? %>
      <div class="crm-sidebar__group">
        <span class="crm-sidebar__group-label">Admin</span>

        <%= link_to users_path, class: "crm-sidebar__link #{'active' if request.path.start_with?(users_path)}" do %>
          <i class="fa-solid fa-user crm-fa"></i>
          Usuários
        <% end %>

        <%= link_to clients_path, class: "crm-sidebar__link #{'active' if request.path.start_with?(clients_path)}" do %>
          <i class="fa-solid fa-building crm-fa"></i>
          Clientes
        <% end %>

        <%= link_to profiles_path, class: "crm-sidebar__link #{'active' if request.path.start_with?(profiles_path)}" do %>
          <i class="fa-solid fa-id-badge crm-fa"></i>
          Perfis
        <% end %>

        <%= link_to '/crm/sidekiq', class: "crm-sidebar__link", target: '_blank' do %>
          <i class="fa-solid fa-bolt crm-fa"></i>
          Sidekiq
        <% end %>

        <%= link_to try_on_index_path, class: "crm-sidebar__link #{'active' if request.path.start_with?(try_on_index_path)}" do %>
          <i class="fa-solid fa-wand-magic-sparkles crm-fa"></i>
          Try-On Virtual
        <% end %>
      </div>
    <% end %>

  </nav>
</aside>
```

- [ ] **Step 2: Reescrever `app/assets/stylesheets/layouts/sidebar.scss`**

```scss
.crm-shell__body {
  display: flex;
  align-items: flex-start;
}

.crm-sidebar {
  width: 240px;
  flex-shrink: 0;
  background: var(--bg);
  border-right: 1px solid var(--outline);
  min-height: calc(100vh - 64px);
  position: sticky;
  top: 64px;
}

.crm-sidebar__nav {
  padding: 16px 12px;
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.crm-sidebar__group {
  margin-top: 12px;
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.crm-sidebar__group-label {
  font-size: 11px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: .06em;
  color: var(--fg-alt);
  padding: 8px 12px 4px;
}

.crm-sidebar__link {
  display: flex;
  align-items: center;
  color: var(--fg);
  text-decoration: none;
  font-weight: 500;
  font-size: 14px;
  padding: 9px 12px;
  border-radius: var(--radius);
  transition: background .15s, color .15s;
}

.crm-sidebar__link:hover {
  background: var(--primary-tint);
  color: var(--primary);
}

.crm-sidebar__link.active {
  background: var(--primary-tint);
  color: var(--primary);
}

.crm-sidebar__link.active .crm-fa,
.crm-sidebar__link:hover .crm-fa {
  color: var(--primary);
}

@media (max-width: 768px) {
  .crm-sidebar {
    display: none;
    position: fixed;
    top: 0;
    left: 0;
    width: 280px;
    height: 100dvh;
    z-index: 180;
    padding-top: 64px;
    box-shadow: 4px 0 20px rgba(0,0,0,0.2);
    transform: translateX(-100%);
    transition: transform 0.3s ease;
  }

  .crm-sidebar.open {
    display: block;
    transform: translateX(0);
  }

  .crm-nav-overlay {
    z-index: 160;
  }
}
```

- [ ] **Step 3: Renderizar a sidebar em `app/views/layouts/application.html.erb`, envolvendo sidebar + conteúdo em `.crm-shell__body`**

```erb
<%# antes (linhas 27-37) %>
  <body>
    <div class="main-background">
      <% if current_user.present? %>
        <%= render 'layouts/partials/header' %>
      <% end %>
      <%= render 'layouts/partials/content' %>
      <% if current_user.present? %>
        <%= render 'layouts/partials/footer' %>
      <% end %>
    </div>
  </body>
</html>
```

```erb
<%# depois %>
  <body>
    <div class="main-background">
      <% if current_user.present? %>
        <%= render 'layouts/partials/header' %>
      <% end %>
      <div class="crm-shell__body">
        <% if current_user.present? %>
          <%= render 'layouts/partials/sidebar' %>
        <% end %>
        <%= render 'layouts/partials/content' %>
      </div>
      <% if current_user.present? %>
        <%= render 'layouts/partials/footer' %>
      <% end %>
    </div>
  </body>
</html>
```

- [ ] **Step 4: Ajustar `app/views/layouts/partials/_content.html.erb` para ocupar o espaço restante ao lado da sidebar**

```erb
<%# antes %>
<section>
  <div class="container-fluid" style="min-height: 100vh; display: flex; flex-direction: column;">
    <div id="modal-holder"></div>
    <% if controller.controller_name != 'sessions' %>
      <%= render 'layouts/partials/messages' %>
    <% end %>
    <%= yield %>
  </div>
</section>
```

```erb
<%# depois %>
<section style="flex: 1; min-width: 0;">
  <div class="container-fluid" style="min-height: calc(100vh - 64px); display: flex; flex-direction: column;">
    <div id="modal-holder"></div>
    <% if controller.controller_name != 'sessions' %>
      <%= render 'layouts/partials/messages' %>
    <% end %>
    <%= yield %>
  </div>
</section>
```

`flex: 1; min-width: 0;` faz o conteúdo ocupar o espaço restante ao lado dos 240px fixos da sidebar (Step 2), evitando overflow horizontal em tabelas largas. `min-height: calc(100vh - 64px)` desconta a altura fixa da topbar (64px, Task 9) para não sobrar espaço extra abaixo do footer.

- [ ] **Step 5: Adicionar `require layouts/sidebar` em `app/assets/stylesheets/admin.scss`** (hoje não está na lista de requires — a sidebar antiga era órfã)

```scss
# antes
 *= require layouts/topbar
 *= require layouts/chosen
```

```scss
# depois
 *= require layouts/topbar
 *= require layouts/sidebar
 *= require layouts/chosen
```

- [ ] **Step 6: Verificar visualmente**

Desktop: sidebar fixa à esquerda com os mesmos itens/grupos de antes (Dashboard, Vendas, Operações, Marketing, Admin), item ativo destacado. Mobile (< 768px): sidebar escondida por padrão, abre como drawer ao clicar no hamburger da topbar, overlay escurece o fundo, fecha ao clicar fora. Logar como afiliado: sidebar mostra só "Meus Eventos".

- [ ] **Step 7: Rodar a suíte de testes**

Run: `bin/rails test`
Expected: `41 runs, ..., 0 failures, 0 errors` (mudança é só de apresentação/estrutura de partial, nenhum teste depende de HTML de navegação).

- [ ] **Step 8: Commit**

```bash
git add app/views/layouts/partials/_sidebar.html.erb app/assets/stylesheets/layouts/sidebar.scss \
  app/views/layouts/application.html.erb app/views/layouts/partials/_content.html.erb app/assets/stylesheets/admin.scss
git commit -m "feat: rebuild left sidebar navigation with tokens, reused from old header nav"
```

---

### Task 11: Footer — migrar para tokens

**Files:**
- Modify: `app/views/layouts/partials/_footer.html.erb` (remove `<style>` inline)
- Create: `app/assets/stylesheets/layouts/footer.scss`
- Modify: `app/assets/stylesheets/admin.scss` (adicionar `require layouts/footer`)

**Interfaces:**
- Consumes: tokens (Task 6).
- Produces: nenhuma outra task depende disso — é uma migração isolada e testável sozinha (visual).

- [ ] **Step 1: Remover o bloco `<style>` de `app/views/layouts/partials/_footer.html.erb` (linhas 64-174), mantendo só o HTML (linhas 1-62)**

O HTML do footer (`<footer class="crm-footer">...</footer>`, linhas 1-62, já atualizado nas Tasks 2 e 3 com `crm_path`/`/crm/sidekiq`) permanece idêntico — só o bloco `<style>...</style>` do final do arquivo é removido.

- [ ] **Step 2: Criar `app/assets/stylesheets/layouts/footer.scss` com o mesmo CSS, usando tokens**

```scss
.crm-footer {
  background: var(--bg);
  border-top: 1px solid var(--outline);
}

.crm-footer__container {
  max-width: 1200px;
  margin: auto;
  padding: 40px 24px;
  display: grid;
  grid-template-columns: 2fr 1fr 1fr 1.4fr;
  gap: 40px;
}

.crm-footer__logo {
  width: 140px;
}

.crm-footer__description {
  margin-top: 10px;
  font-size: 14px;
  line-height: 1.6;
  color: var(--fg-alt);
  max-width: 260px;
}

.crm-footer__column {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.crm-footer__title {
  font-size: 12px;
  font-weight: 700;
  letter-spacing: .08em;
  text-transform: uppercase;
  color: var(--fg-alt);
  margin-bottom: 6px;
}

.crm-footer__link {
  font-size: 14px;
  color: var(--fg);
  text-decoration: none;
  transition: .15s;
}

.crm-footer__link:hover {
  color: var(--primary);
}

.crm-footer__support {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.crm-footer__support-text {
  font-size: 14px;
  color: var(--fg-alt);
}

.crm-footer__whatsapp {
  display: inline-block;
  background: #25d366;
  color: #fff;
  text-decoration: none;
  padding: 10px 16px;
  border-radius: var(--radius);
  font-size: 14px;
  font-weight: 600;
  width: fit-content;
  transition: .15s;
}

.crm-footer__whatsapp:hover {
  background: #1ebe5d;
}

.crm-footer__bottom {
  border-top: 1px solid var(--outline);
  padding: 14px 24px;
  display: flex;
  justify-content: space-between;
  font-size: 12px;
  color: var(--fg-alt);
}

.crm-footer__version {
  opacity: .7;
}

@media (max-width: 900px) {
  .crm-footer__container {
    grid-template-columns: 1fr;
    gap: 28px;
  }

  .crm-footer__bottom {
    flex-direction: column;
    gap: 6px;
    text-align: center;
  }
}
```

- [ ] **Step 3: Adicionar o require em `app/assets/stylesheets/admin.scss`**

```scss
# antes
 *= require layouts/sidebar
 *= require layouts/chosen
```

```scss
# depois
 *= require layouts/sidebar
 *= require layouts/footer
 *= require layouts/chosen
```

- [ ] **Step 4: Verificar visualmente**

Rolar até o final de `/crm` logado: footer com fundo/texto corretos em claro e escuro (alternar pelo botão de tema).

- [ ] **Step 5: Commit**

```bash
git add app/views/layouts/partials/_footer.html.erb app/assets/stylesheets/layouts/footer.scss app/assets/stylesheets/admin.scss
git commit -m "refactor: extract footer styles to tokens-based footer.scss"
```

---

### Task 12: Página institucional (`/`)

**Files:**
- Modify: `app/views/home/index.html.erb` (hoje só tem `<% title 'Home' %>`)
- Create: `app/assets/stylesheets/pages/institutional.scss`
- Modify: `app/assets/stylesheets/admin.scss` (adicionar `require pages/institutional`)

**Interfaces:**
- Consumes: tokens (Task 6), `.crm-btn`/`.crm-btn--primary`, `.crm-card` (Task 8), `new_user_session_path` (rota Devise dentro de `/crm`, Task 1).
- Produces: página pública renderizada em `GET /` (Task 5 já garante que renderiza para qualquer visitante).

- [ ] **Step 1: Reescrever `app/views/home/index.html.erb`**

```erb
<% title 'Mewtda' %>

<div class="crm-institutional">

  <section class="crm-institutional__hero">
    <%= image_tag 'admin/logo-novo.png', class: 'crm-institutional__logo', alt: 'Mewtda' %>
    <h1 class="crm-institutional__headline">Gerencie seu negócio com inteligência</h1>
    <p class="crm-institutional__subheadline">
      A Mewtda ajuda lojas a centralizar pedidos, clientes e campanhas em um só lugar.
    </p>
    <%= link_to 'Entrar', new_user_session_path, class: 'crm-btn crm-btn--primary crm-institutional__cta' %>
  </section>

  <section class="crm-institutional__features">
    <div class="crm-card crm-institutional__feature">
      <i class="fa-solid fa-chart-line crm-institutional__feature-icon"></i>
      <h2>O que é</h2>
      <p>Um painel único para acompanhar vendas, pedidos e o desempenho das suas campanhas.</p>
    </div>
    <div class="crm-card crm-institutional__feature">
      <i class="fa-solid fa-users crm-institutional__feature-icon"></i>
      <h2>Pra quem é</h2>
      <p>Lojas que vendem por Shopify e precisam de visibilidade sobre clientes e pedidos.</p>
    </div>
    <div class="crm-card crm-institutional__feature">
      <i class="fa-solid fa-bullseye crm-institutional__feature-icon"></i>
      <h2>Como ajuda</h2>
      <p>Automação de eventos, afiliados e acompanhamento de campanhas de marketing.</p>
    </div>
  </section>

  <footer class="crm-institutional__footer">
    &copy; <%= Date.today.year %> Mewtda
  </footer>

</div>
```

- [ ] **Step 2: Criar `app/assets/stylesheets/pages/institutional.scss`**

```scss
.crm-institutional {
  max-width: 1100px;
  margin: 0 auto;
  padding: 4rem 1.5rem;
}

.crm-institutional__hero {
  text-align: center;
  padding-bottom: 3rem;
}

.crm-institutional__logo {
  width: 160px;
  margin-bottom: 1.5rem;
}

.crm-institutional__headline {
  font-size: 2.25rem;
  font-weight: 700;
  color: var(--fg);
  margin-bottom: 0.75rem;
}

.crm-institutional__subheadline {
  font-size: 1.05rem;
  color: var(--fg-alt);
  max-width: 520px;
  margin: 0 auto 2rem;
}

.crm-institutional__cta {
  font-size: 1rem;
  padding: 0.75rem 1.75rem;
}

.crm-institutional__features {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 1.5rem;
}

.crm-institutional__feature {
  text-align: center;
}

.crm-institutional__feature-icon {
  font-size: 1.5rem;
  color: var(--primary);
  margin-bottom: 0.75rem;
}

.crm-institutional__feature h2 {
  font-size: 1.05rem;
  font-weight: 700;
  color: var(--fg);
  margin-bottom: 0.5rem;
}

.crm-institutional__feature p {
  font-size: 0.9rem;
  color: var(--fg-alt);
  line-height: 1.5;
}

.crm-institutional__footer {
  margin-top: 4rem;
  padding-top: 2rem;
  border-top: 1px solid var(--outline);
  text-align: center;
  font-size: 0.8rem;
  color: var(--fg-alt);
}

@media (max-width: 768px) {
  .crm-institutional__features {
    grid-template-columns: 1fr;
  }
}
```

- [ ] **Step 3: Adicionar o require em `app/assets/stylesheets/admin.scss`**

```scss
# antes
 *= require layouts/customers
 *= require components/button
```

```scss
# depois
 *= require layouts/customers
 *= require pages/institutional
 *= require components/button
```

Nota: `pages/institutional` precisa vir depois de `tokens` (já garantido, pois `tokens` está bem no início da lista desde a Task 6) e antes ou depois de `components/*` tanto faz, já que não há conflito de seletor entre `.crm-institutional*` e `.crm-btn`/`.crm-card`.

- [ ] **Step 4: Verificar visualmente**

Abrir `/` deslogado: hero com logo, título, subtítulo e botão "Entrar" (leva para `/crm/users/sign_in` — a tela de login já redesenhada, fora de escopo desta task). Três cards de feature abaixo. Rodapé simples. Alternar claro/escuro não é possível aqui (a página institucional não tem o botão de tema, que só existe na topbar do `/crm`) — checar que ainda assim ela respeita o tema salvo no `localStorage` de uma visita anterior ao `/crm` (a classe `.theme-dark` em `<html>` é global ao domínio).

- [ ] **Step 5: Rodar a suíte completa**

Run: `bin/rails test`
Expected: `41 runs, ..., 0 failures, 0 errors`.

- [ ] **Step 6: Commit**

```bash
git add app/views/home/index.html.erb app/assets/stylesheets/pages/institutional.scss app/assets/stylesheets/admin.scss
git commit -m "feat: build public institutional page at root"
```

---

## Área 1 — Dashboard (`app/views/dashboard/index.html.erb`)

## Seção A — Dashboard (`app/views/dashboard/index.html.erb`)

> **Dependência:** todas as tasks abaixo assumem que `app/assets/stylesheets/tokens.scss` e
> `app/assets/stylesheets/components/{_button,_input,_table,_card,_tag}.scss` já existem no
> repo (nenhum dos dois existe ainda — confirmado em `app/assets/stylesheets/`). Se a Seção A
> for executada antes dessas tasks, criar `tokens.scss` e os componentes primeiro, ou adiar A-1..A-7.
>
> **Estado atual de `painel_path`/`painel_session_path`:** o arquivo ainda usa esses helpers
> (linhas 751-754, 759, 780, 1146) apesar do contexto indicar que já viraram `crm_path`/
> `crm_session_path` em outra task. Os snippets abaixo citam o texto exato encontrado hoje no
> arquivo (`painel_path`); se a rename já tiver rodado quando esta seção for executada, ajuste
> só o nome do helper — não é escopo desta seção.

---

### Task 16: Extrair `<style>` para `pages/dashboard.scss` + tabela de substituição

**Files:**
- Create: `app/assets/stylesheets/pages/dashboard.scss`
- Modify: `app/views/dashboard/index.html.erb:3-724` (remove bloco `<style>…</style>` inteiro, incluindo a linha em branco duplicada logo abaixo)
- Modify: `app/assets/stylesheets/admin.scss:23` (adicionar require antes de `require_self`)

**Interfaces:**
- Consumes: `var(--bg)`, `var(--fg)`, `var(--fg-alt)`, `var(--chrome-bg)`, `var(--chrome-fg)`, `var(--outline)`, `var(--primary)`, `var(--primary-tint)`, `var(--radius)` de `tokens.scss`
- Produces: `app/assets/stylesheets/pages/dashboard.scss` — folha de estilo da página, carregada globalmente via `admin.scss`

- [ ] **Step 1: Extrair o CSS bruto para o novo arquivo**
```bash
sed -n '4,722p' app/views/dashboard/index.html.erb > app/assets/stylesheets/pages/dashboard.scss
```
(linhas 4-722 = conteúdo entre as tags `<style>`/`</style>`, sem as tags).

- [ ] **Step 2: Aplicar a tabela de substituição mecânica abaixo em `pages/dashboard.scss`**

Valores encontrados no arquivo e seu destino. "Uso" indica se a ocorrência é cor de **fundo/borda** ou de **texto**, porque alguns hex (`#fff`, `#0f172a`) aparecem nos dois papéis com significados opostos em tema escuro — não faça `sed` cego nesses, edite caso a caso conferindo o seletor.

| Valor original | Uso | Token |
|---|---|---|
| `#ffffff`, `#fff` como **fundo** de card/tabela/modal/badge (ex. `.db-card`, `.db-table-card`, `.db-modal`, `.db-modal__chip`, `.db-event`) | background | `var(--bg)` |
| `#fff` como **texto** sobre painel escuro (`.db-header__title`, `.db-funnel-section__title`, `.db-funnel__count`, `.db-funnel__rate`, `.db-modal__head-title`, `.db-modal__close`) | color | `var(--chrome-fg)` |
| `#e2e8f0` (bordas de card/tabela/filtro/select/badge) | border | `var(--outline)` |
| `#f1f5f9`, `#f8fafc` usados como **borda** ou **divisor** (`border-bottom`, `.db-top-list li`) | border | `var(--outline)` |
| `#f1f5f9` usado como **fundo estático** de chip/placeholder/pre (`.db-top-list__rank`, `.db-top-list__img`, `.db-top-list__img-placeholder`, `.db-badge--mono`, `.db-badge--device`, `.db-event pre`, `.db-top-list--products .db-top-list__count`, `.db-empty__icon`) | background | `var(--outline)` *(não há token de "superfície neutra"; é a aproximação mais próxima — ver nota no resumo)* |
| `#f1f5f9` usado como **hover** (`.db-table tbody tr:hover`) | background | `var(--primary-tint)` *(mesmo padrão do `.crm-table tbody tr:hover` do design system)* |
| `#f8fafc` como fundo estático (`.db-filters`, `.db-month-filter__select`) | background | `var(--outline)` |
| `#94a3b8` (texto secundário/mudo — a maioria das ocorrências) | color | `var(--fg-alt)` |
| `#64748b` (texto secundário mais escuro) | color | `var(--fg-alt)` |
| `#cbd5e1` (ícone do breadcrumb) | color | `var(--fg-alt)` |
| `#475569` (texto de célula de tabela, chip do modal) | color | `var(--fg)` |
| `#334155` (`.db-card__title`) | color | `var(--fg)` |
| `#0f172a` como **texto** (títulos, valores de KPI, `.db-table-card__title`, `.db-empty__title`, chip `strong`) | color | `var(--fg)` |
| `#0f172a` como **fundo** (`.db-month-filter__btn`, `.db-badge--count`, ponto inicial do gradiente `.db-funnel-section`/`.db-modal__head`, tooltip do heatmap) | background | `var(--chrome-bg)` |
| `#1e293b` (hover de `.db-month-filter__btn`, ponto final do gradiente escuro) | background | `var(--chrome-bg)` *(gradiente vira cor sólida — ver nota no resumo)* |
| `border-radius: 12px`, `10px`, `8px`, `7px`, `6px`, `4px`, `3px` (praticamente todos os `border-radius` do arquivo, incl. `.db-card`, `.db-kpi`, `.db-table-card`, `.db-badge`, `.db-heatmap__cell`, `.db-funnel__bar`, `.db-month-filter__*`) | radius | `var(--radius)` |
| `border-radius: 14px`, `16px`, `20px` (`.db-header`, `.db-funnel-section`, `.db-modal`, `.db-empty__icon`) | radius | `var(--radius)` *(decisão de padronizar — ver nota no resumo)* |

Valores **não listados** permanecem como estão — isso inclui as cores de acento de KPI (`#3b82f6`, `#22c55e`, `#f59e0b`, `#f43f5e`, `#8b5cf6`), as cores do funil, `rgba(255,255,255,.08/.1/.2)` sobre o painel escuro, e sombras `box-shadow` (não há token de shadow definido). `.db-header` (`background:#3b4adf`) fica fora desta tabela porque não corresponde a nenhum token — tratado como decisão explícita na Task 17.

- [ ] **Step 3: Remover o bloco `<style>` do ERB**
old_string (linhas 1-6, início do arquivo):
```erb
<% title 'Dashboard Analytics' %>

<style>
  .db-page { padding: 24px 28px; min-height: 100vh; }
  @media (max-width: 600px) { .db-page { padding: 16px; } }
```
new_string:
```erb
<% title 'Dashboard Analytics' %>
```
(e apagar tudo entre esse ponto e o fechamento `</style>` na linha 723, mais a linha em branco duplicada na linha 724-725, deixando a linha 726 `<div class="db-page">` logo em seguida).

- [ ] **Step 4: Registrar o novo stylesheet em `admin.scss`**
old_string:
```
 *= require layouts/customers
 *= require_self
```
new_string:
```
 *= require layouts/customers
 *= require pages/dashboard
 *= require_self
```

- [ ] **Step 5: Verificar visualmente**
Abrir `/painel` (ou `/crm`, conforme o estado da rename) em claro e escuro: a página deve renderizar sem CSS quebrado, sem FOUC, com cards/bordas usando os tons de `tokens.scss` — nesta etapa isolada as cores de acento (KPI, funil, badges) ainda estarão hardcoded, o que é esperado (cobertas nas próximas tasks).

- [ ] **Step 6: Commit**
```bash
git add app/assets/stylesheets/pages/dashboard.scss app/assets/stylesheets/admin.scss app/views/dashboard/index.html.erb
git commit -m "dashboard: move inline <style> to pages/dashboard.scss with token substitution"
```

---

### Task 17: Header, breadcrumb e filtros de período/mês

**Files:**
- Modify: `app/assets/stylesheets/pages/dashboard.scss` (regras `.db-header*`, `.db-filter*`, `.db-month-filter*` — já movidas na Task 16)
- Modify: `app/views/dashboard/index.html.erb:728-787`

**Interfaces:**
- Consumes: `var(--chrome-bg)`, `var(--chrome-fg)`, `var(--outline)`, `var(--fg-alt)`, `var(--primary)`, `var(--radius)`
- Produces: nenhuma (visual only)

- [ ] **Step 1: Decisão — cor de fundo do header**
`.db-header { background: #3b4adf; ... }` (`pages/dashboard.scss`, ex-linha 14) não corresponde a nenhum token do design system (não é `--primary` `#1967d2` nem `--chrome-bg` `#1c2834`). Recomendação: trocar para `background: var(--chrome-bg); border-color: var(--chrome-bg);` para alinhar com o painel escuro do funil/modal e dar consistência visual à página. **Esta é uma decisão de produto, não só técnica — confirmar com o usuário antes de aplicar**, pois muda a cor de destaque do topo da página de roxo/azul (#3b4adf) para o chrome escuro padrão do sistema.
```scss
// old
.db-header {
  ...
  background: #3b4adf;
  border: 1px solid #e2e8f0;
  ...
}
// new
.db-header {
  ...
  background: var(--chrome-bg);
  border: 1px solid var(--chrome-bg);
  ...
}
```

- [ ] **Step 2: Client-name badge — trocar paleta azul fixa por `.crm-tag--neutral`-like tokens**
```scss
// old
.db-header__client-name {
  color: #0369a1;
  font-weight: 600;
  background: #f0f9ff;
  padding: 1px 8px;
  border-radius: 4px;
  border: 1px solid #bae6fd;
  font-size: 12px;
}
// new
.db-header__client-name {
  color: var(--primary);
  font-weight: 600;
  background: var(--primary-tint);
  padding: 1px 8px;
  border-radius: var(--radius);
  border: 1px solid var(--primary);
  font-size: 12px;
}
```

- [ ] **Step 3: Filtros de período (`db-filters`, `db-filter-btn`) — token-ficar cores, manter estrutura de "segmented control"**
```scss
// old
.db-filters {
  display: flex;
  gap: 4px;
  background: #f8fafc;
  border: 1px solid #e2e8f0;
  border-radius: 10px;
  padding: 4px;
}
.db-filter-btn {
  padding: 6px 14px;
  border-radius: 7px;
  border: none;
  background: transparent;
  color: #64748b;
  font-size: 13px;
  font-weight: 500;
  text-decoration: none;
  transition: all .15s;
  white-space: nowrap;
}
.db-filter-btn:hover { background: #fff; color: #1e293b; box-shadow: 0 1px 3px rgba(0,0,0,.06); }
.db-filter-btn--active { background: #fff; color: #0f172a; font-weight: 600; box-shadow: 0 1px 4px rgba(0,0,0,.08); }
// new
.db-filters {
  display: flex;
  gap: 4px;
  background: var(--outline);
  border: 1px solid var(--outline);
  border-radius: var(--radius);
  padding: 4px;
}
.db-filter-btn {
  padding: 6px 14px;
  border-radius: var(--radius);
  border: none;
  background: transparent;
  color: var(--fg-alt);
  font-size: 13px;
  font-weight: 500;
  text-decoration: none;
  transition: all .15s;
  white-space: nowrap;
}
.db-filter-btn:hover { background: var(--bg); color: var(--fg); box-shadow: 0 1px 3px rgba(0,0,0,.06); }
.db-filter-btn--active { background: var(--bg); color: var(--fg); font-weight: 600; box-shadow: 0 1px 4px rgba(0,0,0,.08); }
```
Este componente é um "segmented control" de navegação por links, sem equivalente exato em `_button.scss`/`_tag.scss` — mantido como CSS de página, só com cores tokenizadas.

- [ ] **Step 4: Filtro de mês/ano — token-ficar select e botão "Filtrar"**
```scss
// old
.db-month-filter__select {
  height: 34px;
  padding: 0 28px 0 10px;
  border: 1px solid #e2e8f0;
  border-radius: 8px;
  background: #f8fafc;
  color: #475569;
  font-size: 13px;
  font-weight: 500;
  cursor: pointer;
  appearance: none;
  background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='12' fill='none' stroke='%2394a3b8' stroke-width='2' viewBox='0 0 24 24'%3E%3Cpath d='M6 9l6 6 6-6'/%3E%3C/svg%3E");
  background-repeat: no-repeat;
  background-position: right 8px center;
  transition: all .15s;
}
.db-month-filter__select:focus { outline: none; border-color: #94a3b8; background-color: #fff; }
.db-month-filter__select--active { border-color: #0f172a; background-color: #fff; color: #0f172a; font-weight: 600; }
.db-month-filter__btn {
  display: flex;
  align-items: center;
  gap: 6px;
  height: 34px;
  padding: 0 14px;
  border-radius: 8px;
  border: none;
  background: #0f172a;
  color: #fff;
  font-size: 13px;
  font-weight: 600;
  cursor: pointer;
  transition: background .15s;
  white-space: nowrap;
}
.db-month-filter__btn:hover { background: #1e293b; }
// new
.db-month-filter__select {
  height: 34px;
  padding: 0 28px 0 10px;
  border: 1px solid var(--outline);
  border-radius: var(--radius);
  background: var(--outline);
  color: var(--fg);
  font-size: 13px;
  font-weight: 500;
  cursor: pointer;
  appearance: none;
  background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='12' fill='none' stroke='%236a6f71' stroke-width='2' viewBox='0 0 24 24'%3E%3Cpath d='M6 9l6 6 6-6'/%3E%3C/svg%3E");
  background-repeat: no-repeat;
  background-position: right 8px center;
  transition: all .15s;
}
.db-month-filter__select:focus { outline: none; border-color: var(--primary); background-color: var(--bg); box-shadow: 0 0 0 3px var(--primary-tint); }
.db-month-filter__select--active { border-color: var(--primary); background-color: var(--bg); color: var(--fg); font-weight: 600; }
.db-month-filter__btn {
  display: flex;
  align-items: center;
  gap: 6px;
  height: 34px;
  padding: 0 14px;
  border-radius: var(--radius);
  border: none;
  background: var(--primary);
  color: #fff;
  font-size: 13px;
  font-weight: 600;
  cursor: pointer;
  transition: filter .15s;
  white-space: nowrap;
}
.db-month-filter__btn:hover { filter: brightness(.92); }
```
Nota: o SVG inline embutido no `background-image` tem a cor `%2394a3b8` (`#94a3b8` URL-encoded) hardcoded — trocado manualmente para `%236a6f71` (`--fg-alt` claro `#6a6f71`) porque `url()` não aceita `var()` em `stroke`. Isso significa que o ícone do select **não vai reagir ao tema escuro automaticamente**; se isso importar, mover para um ícone via `::after`/mask-image em vez de background SVG embutido — fica como nota para o usuário decidir, não bloqueia esta task.

- [ ] **Step 5: Botão de limpar filtro — usar paleta danger**
```scss
// old
.db-month-filter__clear {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 28px;
  height: 28px;
  border-radius: 6px;
  border: 1px solid #fca5a5;
  background: #fff1f2;
  color: #ef4444;
  text-decoration: none;
  transition: all .15s;
}
.db-month-filter__clear:hover { background: #fee2e2; }
// new
.db-month-filter__clear {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 28px;
  height: 28px;
  border-radius: var(--radius);
  border: 1px solid #c5221f;
  background: #fce8e6;
  color: #c5221f;
  text-decoration: none;
  transition: all .15s;
}
.db-month-filter__clear:hover { background: #fce8e6; filter: brightness(.95); }
```
`#c5221f`/`#fce8e6` são as mesmas cores de `.crm-tag--danger` (não há token CSS var dedicado a "danger", só existe como classe de componente — usar os valores literais aqui é consistente com o que `_tag.scss` já faz).

- [ ] **Step 6: Verificar visualmente**
Claro e escuro: header com fundo `--chrome-bg`, filtros de período legíveis nos dois temas (texto `--fg-alt`/`--fg` sobre fundo claro do segmented control — atenção: o segmented control usa `var(--outline)` como fundo, que em tema escuro é um cinza escuro sutil, não branco; confirmar contraste do texto ativo). Botão "Filtrar" com `var(--primary)`. Botão de limpar (X vermelho) só aparece quando há filtro de mês ativo — testar navegando com `?year=2026&month=8`.

- [ ] **Step 7: Commit**
```bash
git add app/assets/stylesheets/pages/dashboard.scss
git commit -m "dashboard: token-ify header, breadcrumb and period/month filters"
```

---

### Task 18: Estado vazio (`db-empty`) e KPI cards

**Files:**
- Modify: `app/assets/stylesheets/pages/dashboard.scss` (regras `.db-empty*`, `.db-card*`, `.db-kpi*`)
- Modify: `app/views/dashboard/index.html.erb:790-852`

**Interfaces:**
- Consumes: `var(--bg)`, `var(--fg)`, `var(--fg-alt)`, `var(--outline)`, `var(--radius)`, componente `.crm-tag--*`
- Produces: nenhuma

- [ ] **Step 1: `.db-empty` — token-ficar ícone e textos**
```scss
// old
.db-empty__icon {
  width: 80px;
  height: 80px;
  border-radius: 20px;
  background: #f1f5f9;
  display: flex;
  align-items: center;
  justify-content: center;
  margin-bottom: 24px;
}
.db-empty__icon svg { color: #94a3b8; }
.db-empty__title {
  font-size: 18px;
  font-weight: 700;
  color: #0f172a;
  margin-bottom: 8px;
}
.db-empty__text {
  font-size: 14px;
  color: #64748b;
  max-width: 400px;
  line-height: 1.6;
}
// new
.db-empty__icon {
  width: 80px;
  height: 80px;
  border-radius: var(--radius);
  background: var(--outline);
  display: flex;
  align-items: center;
  justify-content: center;
  margin-bottom: 24px;
}
.db-empty__icon svg { color: var(--fg-alt); }
.db-empty__title {
  font-size: 18px;
  font-weight: 700;
  color: var(--fg);
  margin-bottom: 8px;
}
.db-empty__text {
  font-size: 14px;
  color: var(--fg-alt);
  max-width: 400px;
  line-height: 1.6;
}
```

- [ ] **Step 2: `.db-card` genérico (usado nos gráficos e no card de estado vazio) → alinhar com `.crm-card`**
```scss
// old
.db-card {
  background: #fff;
  border: 1px solid #e2e8f0;
  border-radius: 12px;
  padding: 20px;
  overflow: hidden;
}
.db-card__header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 16px;
}
.db-card__title {
  font-size: 13px;
  font-weight: 600;
  color: #334155;
}
// new
.db-card {
  background: var(--bg);
  border: 1px solid var(--outline);
  border-radius: var(--radius);
  padding: 20px;
  overflow: hidden;
}
.db-card__header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 16px;
}
.db-card__title {
  font-size: 13px;
  font-weight: 600;
  color: var(--fg);
}
```
`.db-card` já é praticamente idêntico a `.crm-card` (mesmo padding, borda, radius) — decisão razoável é deixá-lo como alias de página em vez de trocar todas as ocorrências de `class="db-card"` por `class="crm-card"` no HTML, porque `.db-card` tem filhos próprios (`__header`, `__title`) que `.crm-card` não define. Se preferir consolidar de vez, ver nota no resumo final.

- [ ] **Step 3: Grid de KPIs — token-ficar cores das barras de acento e valores**
```scss
// old
.db-kpi {
  background: #fff;
  border: 1px solid #e2e8f0;
  border-radius: 12px;
  padding: 18px 20px;
  position: relative;
  overflow: hidden;
}
.db-kpi__label {
  font-size: 11px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: .5px;
  color: #94a3b8;
  margin-bottom: 8px;
}
.db-kpi__value {
  font-size: 28px;
  font-weight: 800;
  color: #0f172a;
  line-height: 1;
  margin-bottom: 6px;
}
// new
.db-kpi {
  background: var(--bg);
  border: 1px solid var(--outline);
  border-radius: var(--radius);
  padding: 18px 20px;
  position: relative;
  overflow: hidden;
}
.db-kpi__label {
  font-size: 11px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: .5px;
  color: var(--fg-alt);
  margin-bottom: 8px;
}
.db-kpi__value {
  font-size: 28px;
  font-weight: 800;
  color: var(--fg);
  line-height: 1;
  margin-bottom: 6px;
}
```
As 5 cores de acento (`--blue`/`--green`/`--amber`/`--rose`/`--purple`, linhas 215-219) ficam como estão — são uma paleta categórica (uma por KPI), sem token equivalente no design system fornecido.

- [ ] **Step 4: `.db-kpi__change` → migrar para `.crm-tag`**
As três variantes de mudança percentual mapeiam 1:1 para as tags de status já definidas em `_tag.scss`:

| Classe atual | Substituir por |
|---|---|
| `.db-kpi__change` (base) | manter como wrapper de tamanho/gap, mas remover `background`/`border-radius`/`padding` próprios e usar as de `.crm-tag` |
| `.db-kpi__change--up` | `.crm-tag--success` |
| `.db-kpi__change--down` | `.crm-tag--danger` |
| `.db-kpi__change--neutral` | `.crm-tag--neutral` |

CSS:
```scss
// old
.db-kpi__change {
  font-size: 11px;
  font-weight: 600;
  display: inline-flex;
  align-items: center;
  gap: 3px;
  padding: 2px 6px;
  border-radius: 4px;
}
.db-kpi__change--up { background: #dcfce7; color: #15803d; }
.db-kpi__change--down { background: #fee2e2; color: #dc2626; }
.db-kpi__change--neutral { background: #f1f5f9; color: #64748b; }
// new
.db-kpi__change {
  font-size: 11px;
}
```
(As classes `--up`/`--down`/`--neutral` são removidas do SCSS; o HTML passa a usar `.crm-tag` + o modificador correspondente, ver Step 5.)

- [ ] **Step 5: Trocar classes no HTML — `db-kpi__change--*` por `crm-tag crm-tag--*`**
5 ocorrências em `index.html.erb`, todas seguindo o mesmo padrão `<span class="db-kpi__change db-kpi__change--<%= ... %>">`:
- Linha 822: `db-kpi__change db-kpi__change--<%= sessions_change[:direction] %>` → `db-kpi__change crm-tag crm-tag--<%= sessions_change[:direction] == 'up' ? 'success' : (sessions_change[:direction] == 'down' ? 'danger' : 'neutral') %>`
- Linha 830: idem, trocando `checkout_change[:direction]`
- Linha 838: `db-kpi__change db-kpi__change--neutral` → `db-kpi__change crm-tag crm-tag--neutral`
- Linha 844: `db-kpi__change db-kpi__change--down` → `db-kpi__change crm-tag crm-tag--danger`
- Linha 850: `db-kpi__change db-kpi__change--neutral` → `db-kpi__change crm-tag crm-tag--neutral`

Como o mapeamento `direction → variante` não é 1:1 textual (`up`→`success`, `down`→`danger`, `neutral`→`neutral`), a forma mais limpa é introduzir um helper Ruby local no topo do bloco `<% else %>` (junto de `calc_change`, linha ~807-816):
```erb
<%
  def calc_change(current, previous)
    return { value: 0, direction: 'neutral' } if previous.zero?
    change = ((current - previous).to_f / previous * 100).round(1)
    { value: change.abs, direction: change > 0 ? 'up' : (change < 0 ? 'down' : 'neutral') }
  end

  sessions_change = calc_change(@unique_sessions, @prev_unique_sessions)
  checkout_change = calc_change(@counts[:checkout_completed], @prev_counts[:checkout_completed])
%>
```
new_string (adiciona `tag_variant`):
```erb
<%
  def calc_change(current, previous)
    return { value: 0, direction: 'neutral' } if previous.zero?
    change = ((current - previous).to_f / previous * 100).round(1)
    { value: change.abs, direction: change > 0 ? 'up' : (change < 0 ? 'down' : 'neutral') }
  end

  def tag_variant(direction)
    { 'up' => 'success', 'down' => 'danger', 'neutral' => 'neutral' }[direction]
  end

  sessions_change = calc_change(@unique_sessions, @prev_unique_sessions)
  checkout_change = calc_change(@counts[:checkout_completed], @prev_counts[:checkout_completed])
%>
```
E então cada `<span>` de mudança usa `crm-tag--<%= tag_variant(sessions_change[:direction]) %>` etc. (linhas 822 e 830); as linhas 838, 844 e 850 já têm direção fixa no ERB, então usam a constante diretamente (`crm-tag--neutral`, `crm-tag--danger`, `crm-tag--neutral`).

- [ ] **Step 6: Verificar visualmente**
Claro e escuro: os 5 KPI cards, badges de variação com as cores de sucesso/perigo/neutro do `_tag.scss` (verde/vermelho/cinza), barras de acento coloridas à esquerda de cada card inalteradas. Card de estado vazio (forçar sem dados, ex. cliente sem sessões) com ícone e textos legíveis nos dois temas.

- [ ] **Step 7: Commit**
```bash
git add app/assets/stylesheets/pages/dashboard.scss app/views/dashboard/index.html.erb
git commit -m "dashboard: migrate empty state and KPI cards to design tokens/crm-tag"
```

---

### Task 19: Painel do funil de conversão (`db-funnel-section`)

**Files:**
- Modify: `app/assets/stylesheets/pages/dashboard.scss` (regras `.db-funnel*`)
- Modify: `app/views/dashboard/index.html.erb:855-938`

**Interfaces:**
- Consumes: `var(--chrome-bg)`, `var(--chrome-fg)`
- Produces: nenhuma

- [ ] **Step 1: Fundo do painel — trocar gradiente por `var(--chrome-bg)` sólido**
```scss
// old
.db-funnel-section {
  background: linear-gradient(135deg, #0f172a 0%, #1e293b 100%);
  border-radius: 16px;
  padding: 28px;
  margin-bottom: 24px;
  overflow-x: auto;
  -webkit-overflow-scrolling: touch;
}
// new
.db-funnel-section {
  background: var(--chrome-bg);
  border-radius: var(--radius);
  padding: 28px;
  margin-bottom: 24px;
  overflow-x: auto;
  -webkit-overflow-scrolling: touch;
}
```
Nota: perde o gradiente diagonal sutil (vira cor sólida) — decisão consistente com achatar `.db-header` e `.db-modal__head` para o mesmo `--chrome-bg` (Task 17/A-7). Se o gradiente for importante visualmente, manter `linear-gradient(135deg, var(--chrome-bg) 0%, var(--chrome-bg) 100%)` não muda nada (mesma cor nos dois stops) — só vale a pena manter gradiente com dois tokens se o design system ganhar uma segunda cor de chrome no futuro. Fora de escopo aqui.

- [ ] **Step 2: Título e período — texto sobre chrome usa `var(--chrome-fg)`**
```scss
// old
.db-funnel-section__title {
  font-size: 14px;
  font-weight: 700;
  color: #fff;
  display: flex;
  align-items: center;
  gap: 8px;
}
// new
.db-funnel-section__title {
  font-size: 14px;
  font-weight: 700;
  color: var(--chrome-fg);
  display: flex;
  align-items: center;
  gap: 8px;
}
```
`.db-funnel-section__period` (fundo `rgba(255,255,255,.08)`, texto `#94a3b8`) fica como está — é um chip translúcido sobre o painel escuro, funciona igual nos dois temas por ser relativo a branco; só o texto `#94a3b8` pode opcionalmente virar `var(--chrome-fg)` com opacidade reduzida, mas isso é polimento, não obrigatório.

- [ ] **Step 3: Contadores, nomes e taxas do funil — texto branco/cinza sobre chrome**
```scss
// old
.db-funnel__count {
  font-size: 32px;
  font-weight: 800;
  color: #fff;
  line-height: 1;
  margin-bottom: 4px;
}
...
.db-funnel__name {
  font-size: 11px;
  color: #94a3b8;
  font-weight: 500;
  text-align: center;
  margin-bottom: 12px;
}
...
.db-funnel__rate {
  font-size: 13px;
  font-weight: 700;
  color: #fff;
  margin-bottom: 4px;
}
// new
.db-funnel__count {
  font-size: 32px;
  font-weight: 800;
  color: var(--chrome-fg);
  line-height: 1;
  margin-bottom: 4px;
}
...
.db-funnel__name {
  font-size: 11px;
  color: var(--chrome-fg);
  opacity: .65;
  font-weight: 500;
  text-align: center;
  margin-bottom: 12px;
}
...
.db-funnel__rate {
  font-size: 13px;
  font-weight: 700;
  color: var(--chrome-fg);
  margin-bottom: 4px;
}
```

- [ ] **Step 4: Manter como está — paleta categórica dos ícones/barras do funil**
As cores por etapa (`#3b82f6`, `#22c55e`, `#f59e0b`, `#ec4899`, usadas em `background:rgba(...)` inline nos ícones — linhas 870, 882, 901, 920 — e em `stroke="#..."` dos SVGs, e em `.db-funnel__bar-fill` inline `style="...background:#22c55e"` etc.) permanecem hardcoded. É uma paleta categórica (uma cor por etapa do funil), sem token equivalente no design system fornecido — mudar isso é uma decisão de paleta de dataviz, não de tokenização, e fica fora do escopo desta task.

- [ ] **Step 5: Verificar visualmente**
Claro e escuro: o painel do funil deve ficar visualmente idêntico ao trocar de tema (ele já é "sempre escuro" por design — é o único painel com fundo chrome fixo independente do tema da página). Conferir contraste do texto `--chrome-fg` sobre `--chrome-bg` nos dois temas (os valores de `--chrome-bg`/`--chrome-fg` mudam entre claro/escuro pelos tokens, então o painel muda de tom sutilmente entre os dois modos).

- [ ] **Step 6: Commit**
```bash
git add app/assets/stylesheets/pages/dashboard.scss
git commit -m "dashboard: token-ify funnel panel background and text (chrome surface)"
```

---

### Task 20: Grids de gráficos, listas de top produtos e heatmap por hora

**Files:**
- Modify: `app/assets/stylesheets/pages/dashboard.scss` (regras `.db-grid-*`, `.db-chart-wrap`, `.db-top-list*`, `.db-heatmap*`)
- Modify: `app/views/dashboard/index.html.erb:941-1090`

**Interfaces:**
- Consumes: `var(--bg)`, `var(--fg)`, `var(--fg-alt)`, `var(--outline)`, `var(--radius)`
- Produces: nenhuma

- [ ] **Step 1: Listas de top produtos — token-ficar texto/bordas/placeholders**
```scss
// old
.db-top-list li {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 10px 0;
  border-bottom: 1px solid #f1f5f9;
  font-size: 13px;
}
.db-top-list__rank {
  width: 22px;
  height: 22px;
  border-radius: 6px;
  background: #f1f5f9;
  color: #64748b;
  font-size: 11px;
  font-weight: 700;
  display: flex;
  align-items: center;
  justify-content: center;
  margin-right: 10px;
  flex-shrink: 0;
}
.db-top-list__title {
  flex: 1;
  color: #334155;
  font-weight: 500;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  max-width: 180px;
}
.db-top-list__count {
  font-weight: 700;
  color: #0f172a;
}
// new
.db-top-list li {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 10px 0;
  border-bottom: 1px solid var(--outline);
  font-size: 13px;
}
.db-top-list__rank {
  width: 22px;
  height: 22px;
  border-radius: var(--radius);
  background: var(--outline);
  color: var(--fg-alt);
  font-size: 11px;
  font-weight: 700;
  display: flex;
  align-items: center;
  justify-content: center;
  margin-right: 10px;
  flex-shrink: 0;
}
.db-top-list__title {
  flex: 1;
  color: var(--fg);
  font-weight: 500;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  max-width: 180px;
}
.db-top-list__count {
  font-weight: 700;
  color: var(--fg);
}
```

- [ ] **Step 2: Placeholders/imagens/preço/SKU de produto — mesmo tratamento**
```scss
// old
.db-top-list__img { ...; background: #f1f5f9; }
.db-top-list__img-placeholder { ...; background: #f1f5f9; ...; color: #94a3b8; }
.db-top-list--products .db-top-list__title { ...; color: #0f172a; }
.db-top-list__sku { font-size: 11px; color: #94a3b8; font-family: monospace; }
.db-top-list__price { font-size: 11px; color: #64748b; }
.db-top-list--products .db-top-list__count {
  font-size: 14px;
  font-weight: 700;
  color: #0f172a;
  background: #f1f5f9;
  padding: 4px 10px;
  border-radius: 6px;
  margin-left: 8px;
}
// new
.db-top-list__img { ...; background: var(--outline); }
.db-top-list__img-placeholder { ...; background: var(--outline); ...; color: var(--fg-alt); }
.db-top-list--products .db-top-list__title { ...; color: var(--fg); }
.db-top-list__sku { font-size: 11px; color: var(--fg-alt); font-family: monospace; }
.db-top-list__price { font-size: 11px; color: var(--fg-alt); }
.db-top-list--products .db-top-list__count {
  font-size: 14px;
  font-weight: 700;
  color: var(--fg);
  background: var(--outline);
  padding: 4px 10px;
  border-radius: var(--radius);
  margin-left: 8px;
}
```

- [ ] **Step 3: Extrair estado "Sem dados" repetido para uma classe**
`index.html.erb:1008` e `:1048` têm o mesmo `style=` inline:
```erb
<p style="color:#94a3b8; font-size:13px; text-align:center; padding:32px 0">Sem dados</p>
```
Adicionar em `pages/dashboard.scss`:
```scss
.db-empty-note { color: var(--fg-alt); font-size: 13px; text-align: center; padding: 32px 0; }
```
E trocar as duas ocorrências (linhas 1008 e 1048) para:
```erb
<p class="db-empty-note">Sem dados</p>
```

- [ ] **Step 4: Heatmap — labels e wrapper, manter escala de cor como está**
```scss
// old
.db-heatmap__cell {
  ...
  color: #64748b;
  ...
}
.db-heatmap__cell:hover::after {
  ...
  background: #0f172a;
  color: #fff;
  ...
}
.db-heatmap__label {
  text-align: center;
  font-size: 9px;
  color: #94a3b8;
}
// new
.db-heatmap__cell {
  ...
  color: var(--fg-alt);
  ...
}
.db-heatmap__cell:hover::after {
  ...
  background: var(--chrome-bg);
  color: var(--chrome-fg);
  ...
}
.db-heatmap__label {
  text-align: center;
  font-size: 9px;
  color: var(--fg-alt);
}
```
A escala de cor por intensidade (`index.html.erb:1063-1074`, variável Ruby `bg`/`text_color` com `#f1f5f9`/`#dbeafe`/`#93c5fd`/`#3b82f6`/`#1d7a3e`... na verdade `#1d4ed8`) fica **fora de escopo** — é uma escala sequencial de dataviz calculada em Ruby, não tem token equivalente (o design system não define uma escala sequencial). Mantida como está.

- [ ] **Step 5: `.db-chart-wrap` e grids — sem cor hardcoded, revisar apenas se necessário**
`.db-grid-2`, `.db-grid-3`, `.db-chart-wrap` não têm cores hardcoded (só `display: grid`/`gap`/`min-height`) — nenhuma mudança necessária além do que a Task 16 já cobre.

- [ ] **Step 6: Verificar visualmente**
Claro e escuro: listas de top produtos (com e sem imagem), placeholders de imagem, tooltip do heatmap ao passar o mouse sobre uma célula, mensagem "Sem dados" quando não há produtos vistos/carrinho no período (forçar filtrando um período sem dados).

- [ ] **Step 7: Commit**
```bash
git add app/assets/stylesheets/pages/dashboard.scss app/views/dashboard/index.html.erb
git commit -m "dashboard: token-ify chart grid, top-product lists and hourly heatmap"
```

---

### Task 21: Tabela de sessões recentes + badges de status

**Files:**
- Modify: `app/assets/stylesheets/pages/dashboard.scss` (regras `.db-table-card*`, `.db-table*`, `.db-badge*`)
- Modify: `app/views/dashboard/index.html.erb:1114-1189`
- Modify: `app/views/dashboard/index.html.erb:1282-1290` (`KIND_BADGE` no `<script>`, precisa ficar consistente com as classes trocadas no ERB)

**Interfaces:**
- Consumes: `.crm-table` (`components/_table.scss`), `.crm-tag--{success,danger,warning,neutral}` (`components/_tag.scss`), `var(--bg)`, `var(--fg)`, `var(--fg-alt)`, `var(--outline)`, `var(--radius)`
- Produces: nenhuma

- [ ] **Step 1: `.db-table-card` — token-ficar container**
```scss
// old
.db-table-card {
  background: #fff;
  border: 1px solid #e2e8f0;
  border-radius: 12px;
  overflow: hidden;
  margin-bottom: 24px;
}
.db-table-card__header {
  padding: 16px 20px;
  border-bottom: 1px solid #f1f5f9;
  display: flex;
  align-items: center;
  justify-content: space-between;
  flex-wrap: wrap;
  gap: 8px;
}
.db-table-card__title { font-size: 14px; font-weight: 700; color: #0f172a; }
.db-table-card__count { font-size: 12px; color: #94a3b8; }
// new
.db-table-card {
  background: var(--bg);
  border: 1px solid var(--outline);
  border-radius: var(--radius);
  overflow: hidden;
  margin-bottom: 24px;
}
.db-table-card__header {
  padding: 16px 20px;
  border-bottom: 1px solid var(--outline);
  display: flex;
  align-items: center;
  justify-content: space-between;
  flex-wrap: wrap;
  gap: 8px;
}
.db-table-card__title { font-size: 14px; font-weight: 700; color: var(--fg); }
.db-table-card__count { font-size: 12px; color: var(--fg-alt); }
```

- [ ] **Step 2: Adotar `.crm-table` como base da tabela em vez de `.db-table` próprio**
`.db-table` (linhas 563-601) reimplementa exatamente o que `.crm-table` já faz (`border-collapse`, `th` uppercase cinza com borda inferior, `td` com padding/borda, hover de linha). Trocar a classe no HTML e reduzir `.db-table` a só os extras que `.crm-table` não cobre (`min-width`, `.center`, estado abandonado, empty state):
```scss
// old (remover integralmente — vira .crm-table)
.db-table {
  width: 100%;
  border-collapse: collapse;
  min-width: 700px;
}
.db-table thead th {
  padding: 12px 16px;
  text-align: left;
  font-size: 10px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: .6px;
  color: #94a3b8;
  background: #fff;
  border-bottom: 1px solid #e2e8f0;
}
.db-table thead th.center { text-align: center; }
.db-table tbody tr {
  border-bottom: 1px solid #f1f5f9;
  transition: background .1s;
  cursor: pointer;
}
.db-table tbody tr:last-child { border-bottom: none; }
.db-table tbody tr:hover { background: #f1f5f9; }
.db-table tbody tr.db-table__row--abandoned { background: #fef2f2; }
.db-table tbody tr.db-table__row--abandoned:hover { background: #fee2e2; }
.db-table td {
  padding: 14px 16px;
  font-size: 13px;
  color: #475569;
  vertical-align: middle;
}
.db-table td.center { text-align: center; }
.db-table__empty {
  text-align: center;
  padding: 48px;
  color: #94a3b8;
  font-size: 14px;
}
// new (só os extras específicos desta página, o resto vem de .crm-table)
.db-table { min-width: 700px; }
.db-table th.center, .db-table td.center { text-align: center; }
.db-table tbody tr { cursor: pointer; }
.db-table tbody tr.db-table__row--abandoned { background: #fce8e6; }
.db-table tbody tr.db-table__row--abandoned:hover { background: #fce8e6; filter: brightness(.97); }
.db-table__empty {
  text-align: center;
  padding: 48px;
  color: var(--fg-alt);
  font-size: 14px;
}
```

- [ ] **Step 3: Trocar `class="db-table"` por `class="db-table crm-table"` no HTML**
`index.html.erb:1121`:
```erb
<!-- old -->
<table class="db-table">
<!-- new -->
<table class="db-table crm-table">
```

- [ ] **Step 4: Migrar badges de status para `.crm-tag`**
Tabela de mapeamento (badges que são realmente "status", com equivalente direto em `_tag.scss`):

| Classe atual | Cor atual | Substituir por |
|---|---|---|
| `.db-badge--product` | `#dcfce7`/`#15803d` | `.crm-tag--success` |
| `.db-badge--cart` | `#fef3c7`/`#b45309` | `.crm-tag--warning` |
| `.db-badge--abandoned` | `#fee2e2`/`#dc2626` | `.crm-tag--danger` |

Badges que **não** têm equivalente em `_tag.scss` (só existem success/danger/warning/neutral, não há uma cor "info" azul/rosa). Decisão aplicada abaixo: variantes de página (`db-badge--info` etc.) em `pages/dashboard.scss`, reaproveitando os mesmos tokens que `.crm-tag--info` (Task 8) usa, em vez de achatar para `--neutral`/`--success` e perder a distinção de cor:

| Classe atual | Cor atual | Situação |
|---|---|---|
| `.db-badge--page` | `#dbeafe`/`#1d4ed8` (azul) | sem variante — proposta: nova `.crm-tag--info` de página (`background:#e8f0fe; color:#1967d2;`, usando a cor de `--primary`) |
| `.db-badge--checkout` | `#fce7f3`/`#be185d` (rosa) | sem variante — proposta: manter como `.db-badge--checkout` custom (não é um "tag" de status geral, é específico desta tabela) |
| `.db-badge--count` | `#0f172a`/`#fff` (pílula escura para número de eventos) | não é status, é contador — manter custom, token-ficar: `background: var(--chrome-bg); color: var(--chrome-fg);` |
| `.db-badge--mono` (SID truncado) | `#f1f5f9`/`#475569` monospace | não é status, é código — manter custom, token-ficar: `background: var(--outline); color: var(--fg);` |
| `.db-badge--device` | `#f1f5f9`/`#64748b` | não é status, é metadado — manter custom, token-ficar: `background: var(--outline); color: var(--fg-alt);` |

CSS resultante:
```scss
// old
.db-badge {
  display: inline-block;
  padding: 3px 8px;
  border-radius: 6px;
  font-size: 11px;
  font-weight: 600;
}
.db-badge--mono { font-family: monospace; background: #f1f5f9; color: #475569; }
.db-badge--page    { background: #dbeafe; color: #1d4ed8; }
.db-badge--product { background: #dcfce7; color: #15803d; }
.db-badge--cart    { background: #fef3c7; color: #b45309; }
.db-badge--checkout{ background: #fce7f3; color: #be185d; }
.db-badge--count   { background: #0f172a; color: #fff; }
.db-badge--abandoned { background: #fee2e2; color: #dc2626; }
.db-badge--device  { background: #f1f5f9; color: #64748b; font-size: 10px; }
// new
.db-badge {
  display: inline-block;
  padding: 3px 8px;
  border-radius: var(--radius);
  font-size: 11px;
  font-weight: 600;
}
.db-badge--mono   { font-family: monospace; background: var(--outline); color: var(--fg); }
.db-badge--info   { background: var(--primary-tint); color: var(--primary); }
.db-badge--checkout{ background: #fce7f3; color: #be185d; }
.db-badge--count  { background: var(--chrome-bg); color: var(--chrome-fg); }
.db-badge--device { background: var(--outline); color: var(--fg-alt); font-size: 10px; }
```
(`.db-badge--product`, `--cart`, `--abandoned` são removidas daqui — viram `crm-tag--success`/`--warning`/`--danger` diretamente no HTML e no JS.)

- [ ] **Step 5: Trocar `badge_class` no ERB (linhas 1156-1165)**
```erb
<!-- old -->
<%
  badge_class = case kind
    when 'page_viewed'           then 'db-badge--page'
    when 'product_viewed'        then 'db-badge--product'
    when 'product_added_to_cart' then 'db-badge--cart'
    when 'checkout_started'      then 'db-badge--cart'
    when 'checkout_completed'    then 'db-badge--checkout'
    else ''
  end
%>
<span class="db-badge <%= badge_class %>"><%= kind.split('_').first(2).join(' ') %></span>
<!-- new -->
<%
  badge_class = case kind
    when 'page_viewed'           then 'db-badge--info'
    when 'product_viewed'        then 'crm-tag crm-tag--success'
    when 'product_added_to_cart' then 'crm-tag crm-tag--warning'
    when 'checkout_started'      then 'crm-tag crm-tag--warning'
    when 'checkout_completed'    then 'db-badge--checkout'
    else ''
  end
%>
<span class="db-badge <%= badge_class %>"><%= kind.split('_').first(2).join(' ') %></span>
```

- [ ] **Step 6: Badge "converteu" inline (linha 1180) — remover `style=` duplicado, usar classe**
Achado durante a leitura: esta badge já duplica as cores de `.db-badge--product`/`crm-tag--success` via `style=` inline em vez de reusar uma classe.
```erb
<!-- old -->
<% if s[:abandoned] %>
  <span class="db-badge db-badge--abandoned">nao converteu</span>
<% else %>
  <span class="db-badge" style="background:#dcfce7; color:#15803d">converteu</span>
<% end %>
<!-- new -->
<% if s[:abandoned] %>
  <span class="crm-tag crm-tag--danger">nao converteu</span>
<% else %>
  <span class="crm-tag crm-tag--success">converteu</span>
<% end %>
```

- [ ] **Step 7: Badges de device/contagem/SID — só trocar classes wrapper, sem mudar cor (já cobertas pelo CSS do Step 4)**
Linhas 1149, 1170, 1174 (`db-badge--mono`, `db-badge--device`, `db-badge--count`) não mudam de classe, só herdam as novas cores tokenizadas do Step 4 — nenhuma edição de HTML necessária aqui.

- [ ] **Step 8: Atualizar `KIND_BADGE` no `<script>` (linhas ~1284-1290) para ficar consistente com o Step 5**
Esse objeto é usado pelo JS do modal (`renderEvent`, ao montar o timeline de eventos da sessão) e precisa das mesmas classes novas, senão o modal mostra badges com cores antigas enquanto a tabela já usa as novas:
```js
// old
var KIND_BADGE = {
  page_viewed:           'db-badge--page',
  product_viewed:        'db-badge--product',
  product_added_to_cart: 'db-badge--cart',
  checkout_started:      'db-badge--cart',
  checkout_completed:    'db-badge--checkout'
};
// new
var KIND_BADGE = {
  page_viewed:           'db-badge--info',
  product_viewed:        'crm-tag crm-tag--success',
  product_added_to_cart: 'crm-tag crm-tag--warning',
  checkout_started:      'crm-tag crm-tag--warning',
  checkout_completed:    'db-badge--checkout'
};
```

- [ ] **Step 9: Verificar visualmente**
Claro e escuro: tabela de sessões com hover usando `var(--primary-tint)` (herdado de `.crm-table`), linhas abandonadas com fundo rosado, badges de jornada (página/produto/carrinho/checkout) com as novas cores, badge "converteu"/"não converteu", badge de contagem de eventos (pílula escura), badge de dispositivo. Abrir o modal de uma sessão (clique na linha) e conferir que os badges do timeline de eventos batem com os da tabela.

- [ ] **Step 10: Commit**
```bash
git add app/assets/stylesheets/pages/dashboard.scss app/views/dashboard/index.html.erb
git commit -m "dashboard: adopt crm-table/crm-tag for sessions table and status badges"
```

---

### Task 22: Modal de detalhes da sessão

**Files:**
- Modify: `app/assets/stylesheets/pages/dashboard.scss` (regras `.db-modal*`, `.db-event*`)
- Modify: `app/views/dashboard/index.html.erb:1196-1214`
- Modify: `app/views/dashboard/index.html.erb:1294-1295` (função `chip()` no `<script>`)

**Interfaces:**
- Consumes: `var(--bg)`, `var(--fg)`, `var(--fg-alt)`, `var(--chrome-bg)`, `var(--chrome-fg)`, `var(--outline)`, `var(--radius)`
- Produces: nenhuma

- [ ] **Step 1: Container e cabeçalho do modal**
```scss
// old
.db-modal {
  background: #fff;
  max-width: 820px;
  margin: 40px auto;
  border-radius: 16px;
  box-shadow: 0 25px 80px rgba(0,0,0,.25);
  overflow: hidden;
}
...
.db-modal__head {
  background: linear-gradient(135deg, #0f172a 0%, #1e293b 100%);
  padding: 24px;
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
}
.db-modal__head-title { font-size: 16px; font-weight: 800; color: #fff; margin: 0 0 4px; }
.db-modal__head-sid { font-size: 11px; color: #64748b; font-family: monospace; word-break: break-all; }
// new
.db-modal {
  background: var(--bg);
  max-width: 820px;
  margin: 40px auto;
  border-radius: var(--radius);
  box-shadow: 0 25px 80px rgba(0,0,0,.25);
  overflow: hidden;
}
...
.db-modal__head {
  background: var(--chrome-bg);
  padding: 24px;
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
}
.db-modal__head-title { font-size: 16px; font-weight: 800; color: var(--chrome-fg); margin: 0 0 4px; }
.db-modal__head-sid { font-size: 11px; color: var(--chrome-fg); opacity: .6; font-family: monospace; word-break: break-all; }
```
Mesmo achatamento de gradiente→sólido da Task 19/A-2, para consistência entre os três painéis "chrome" da página (header, funil, modal).

- [ ] **Step 2: Chip de metadados e corpo do modal**
```scss
// old
.db-modal__meta {
  display: flex;
  gap: 12px;
  flex-wrap: wrap;
  padding: 16px 24px;
  border-bottom: 1px solid #f1f5f9;
}
.db-modal__chip {
  font-size: 12px;
  background: #fff;
  border: 1px solid #e2e8f0;
  border-radius: 8px;
  padding: 8px 12px;
  color: #475569;
}
.db-modal__chip strong { color: #0f172a; }
.db-modal__body { padding: 24px; }
.db-modal__section-title {
  font-size: 11px;
  font-weight: 700;
  color: #94a3b8;
  text-transform: uppercase;
  letter-spacing: .6px;
  margin: 0 0 16px;
}
.db-modal__loading { text-align: center; padding: 56px; color: #94a3b8; font-size: 14px; }
// new
.db-modal__meta {
  display: flex;
  gap: 12px;
  flex-wrap: wrap;
  padding: 16px 24px;
  border-bottom: 1px solid var(--outline);
}
.db-modal__chip {
  font-size: 12px;
  background: var(--bg);
  border: 1px solid var(--outline);
  border-radius: var(--radius);
  padding: 8px 12px;
  color: var(--fg);
}
.db-modal__chip strong { color: var(--fg); }
.db-modal__body { padding: 24px; }
.db-modal__section-title {
  font-size: 11px;
  font-weight: 700;
  color: var(--fg-alt);
  text-transform: uppercase;
  letter-spacing: .6px;
  margin: 0 0 16px;
}
.db-modal__loading { text-align: center; padding: 56px; color: var(--fg-alt); font-size: 14px; }
```

- [ ] **Step 3: `chip()` no JS (linha ~1294-1295) — mesma cor "label" que o CSS**
```js
// old
function chip(label, value) {
  return '<div class="db-modal__chip"><span style="color:#94a3b8">' + label + '</span> <strong>' + value + '</strong></div>';
}
// new
function chip(label, value) {
  return '<div class="db-modal__chip"><span style="color:var(--fg-alt)">' + label + '</span> <strong>' + value + '</strong></div>';
}
```

- [ ] **Step 4: Cards de evento na timeline (`.db-event*`)**
```scss
// old
.db-event {
  border: 1px solid #e2e8f0;
  border-radius: 10px;
  padding: 16px;
  margin-bottom: 12px;
  background: #fff;
  transition: box-shadow .15s;
}
.db-event__time { font-size: 11px; color: #94a3b8; }
.db-event__row { font-size: 12px; color: #475569; margin-bottom: 6px; line-height: 1.5; }
.db-event__row a { color: #3b82f6; }
.db-event__row--muted { color: #94a3b8; word-break: break-all; font-size: 11px; }
.db-event summary { font-size: 12px; color: #64748b; cursor: pointer; user-select: none; margin-top: 8px; }
.db-event pre {
  background: #f1f5f9;
  border: 1px solid #e2e8f0;
  border-radius: 6px;
  padding: 12px;
  font-size: 11px;
  overflow: auto;
  margin: 8px 0 0;
  line-height: 1.5;
}
// new
.db-event {
  border: 1px solid var(--outline);
  border-radius: var(--radius);
  padding: 16px;
  margin-bottom: 12px;
  background: var(--bg);
  transition: box-shadow .15s;
}
.db-event__time { font-size: 11px; color: var(--fg-alt); }
.db-event__row { font-size: 12px; color: var(--fg); margin-bottom: 6px; line-height: 1.5; }
.db-event__row a { color: var(--primary); }
.db-event__row--muted { color: var(--fg-alt); word-break: break-all; font-size: 11px; }
.db-event summary { font-size: 12px; color: var(--fg-alt); cursor: pointer; user-select: none; margin-top: 8px; }
.db-event pre {
  background: var(--outline);
  border: 1px solid var(--outline);
  border-radius: var(--radius);
  padding: 12px;
  font-size: 11px;
  overflow: auto;
  margin: 8px 0 0;
  line-height: 1.5;
}
```

- [ ] **Step 5: Overlay — manter como está**
`.db-modal-overlay { background: rgba(15,23,42,.6); backdrop-filter: blur(4px); ... }` (linha ~623) permanece sem mudança — é um scrim semitransparente sobre o app inteiro, funciona igual nos dois temas.

- [ ] **Step 6: Verificar visualmente**
Claro e escuro: abrir o modal de uma sessão, conferir cabeçalho escuro (`--chrome-bg`/`--chrome-fg`), chips de metadados, timeline de eventos com badges (herdadas da Task 21), bloco `<pre>` de dados JSON expandido via `<details>`, botão de fechar (X) e fechamento por clique fora/Esc continuam funcionando (comportamento não foi tocado).

- [ ] **Step 7: Commit**
```bash
git add app/assets/stylesheets/pages/dashboard.scss app/views/dashboard/index.html.erb
git commit -m "dashboard: token-ify session detail modal and event timeline"
```

---

## Área 2 — Eventos (`app/views/events/index.html.erb`)

## Notas gerais sobre `app/views/events/index.html.erb`

- Arquivo tem 1706 linhas. `<style>` vai de `app/views/events/index.html.erb:3` a `app/views/events/index.html.erb:883` (881 linhas de CSS).
- **Esta view não usa nenhuma classe Bootstrap** — é 100% CSS bespoke (`.ev-*`), então a regra "trocar classes Bootstrap puras por `.crm-*`" não tem alvo direto aqui. Em compensação há bastante oportunidade de trocar classes bespoke por `.crm-btn`/`.crm-input`/`.crm-tag` onde o papel visual é idêntico (botões de ação, inputs, badges de status) — ver Tasks B-2 e B-4.
- Não existe declaração `font-family` no seletor raiz desta view (`.ev-page` não define `font-family`), então a instrução de remover a `font-family` do seletor raiz **não se aplica** — nada a remover nesse quesito.
- **Decisão pendente para o usuário** (documentada inline nas tasks abaixo, aplicada com um default razoável mas reversível):
  1. A view usa uma paleta "info" azul-céu própria (`#0369a1` / `#f0f9ff` / `#bae6fd` / `#e0f2fe`) em todo o Gerador de Link de Afiliado e nos chips de UTM/cliente. Não existe token equivalente a "info" no design system fornecido (só `--primary` azul `#1967d2`, mais neutros e as 4 variantes de `.crm-tag`). Default adotado: `#0369a1` → `var(--primary)`, `#f0f9ff` → `var(--primary-tint)`; as bordas `#bae6fd`/`#e0f2fe` (sem token de "borda tintada" equivalente) ficam literais.
  2. A cor indigo do breadcrumb/back-button (`#3b4adf`, `#f0f2fb`, `#dde1f5`) tem o mesmo problema — sem token dedicado. Default: absorver dentro de `.crm-btn--secondary` (Task 26) e mapear o link de breadcrumb para `var(--primary)`.
  3. As cores categóricas decorativas — faixas de KPI (azul/verde/âmbar/rosa/roxo), ícones do funil, badges de "tipo de evento" (page/product/cart/checkout/discount/mono/device/count), a escala de intensidade do heatmap e as cores do ApexCharts (JS) — **não têm equivalente no token set fornecido** (que só define 1 cor primária + 4 variantes de tag). Ficam literais/inalteradas por design; ver nota em cada task. Se o usuário quiser um "accent palette" formal para essas categorias, é uma decisão de design fora do escopo deste plano.
  4. Vários `style="display:none"` são alternados via JS (`el.style.display = 'block'/'none'`) — **não podem virar classes** sem reescrever JS, o que está fora de escopo. Ficam como estão.

---

### Task 23: Extrair o bloco `<style>` (881 linhas) para `pages/events.scss`

**Files:**
- Create: `app/assets/stylesheets/pages/events.scss`
- Modify: `app/views/events/index.html.erb:3-883` (remover bloco `<style>`)
- Modify: `app/assets/stylesheets/admin.scss` (adicionar require)

**Interfaces:**
- Consumes: tokens `--bg`, `--fg`, `--fg-alt`, `--outline`, `--chrome-bg`, `--chrome-fg`, `--primary`, `--primary-tint`, `--radius` de `app/assets/stylesheets/tokens.scss` (definidos em outra task do mesmo plano).
- Produces: folha `pages/events.scss` carregada globalmente pelo manifest Sprockets `admin.scss`; todos os seletores `.ev-*` mantêm o nome exato, então nenhuma outra parte do HTML precisa mudar por causa desta task.

- [ ] **Step 1: Criar `app/assets/stylesheets/pages/events.scss` com o conteúdo movido**

Copiar o conteúdo integral de `app/views/events/index.html.erb:4-882` (todas as regras, sem as tags `<style>`/`</style>`) para o novo arquivo, aplicando a tabela de substituição mecânica abaixo. Qualquer valor de cor não listado na tabela permanece literal (são cores categóricas/decorativas sem token equivalente — ver nota geral no topo deste documento).

**Tabela de substituição — cores:**

| Valor atual | Papel no arquivo | Token |
|---|---|---|
| `#fff` / `#ffffff` usado como `background` (headers, cards, inputs, modal, link-generator) | fundo de superfície | `var(--bg)` |
| `#fff` usado como `color` sobre superfícies escuras (`.ev-funnel-section__title`, `.ev-funnel__count`, `.ev-modal__head-title`, `.ev-modal__close`, `.ev-month-filter__btn`, `.ev-badge--count`) | texto sobre chrome escuro | `var(--chrome-fg)` |
| `#0f172a` usado como `color` (títulos, valores de KPI, `.ev-header__title`, `.ev-table-card__title`, etc.) | texto principal | `var(--fg)` |
| `#0f172a` usado como `background` sólido (`.ev-month-filter__btn`, `.ev-badge--count`, tooltip do heatmap `.ev-heatmap__cell:hover::after`) | superfície chrome escura | `var(--chrome-bg)` |
| `#0f172a` dentro de `linear-gradient(...)` (`.ev-funnel-section`, `.ev-modal__head`) | gradiente decorativo | **deixar literal** (sem token de gradiente) |
| `#94a3b8` | texto secundário/mutado | `var(--fg-alt)` |
| `#64748b` | texto secundário/mutado (tom mais escuro) | `var(--fg-alt)` |
| `#475569` | texto de corpo (tabela, chips) | `var(--fg)` |
| `#334155` | título de card | `var(--fg)` |
| `#e2e8f0` | borda | `var(--outline)` |
| `#f1f5f9` (borda, divisor, fundo neutro claro — hover de linha, badge mono, fundo do rank do top-list, fundo do `<pre>`) | neutro claro | `var(--outline)` |
| `#f8fafc` | fundo neutro claro (filtros de período) | `var(--outline)` |
| `#3b4adf` (`.ev-breadcrumb-link`, `.ev-back-btn` texto) | link/ação indigo | `var(--primary)` |
| `#f0f2fb` (`.ev-back-btn` fundo) | tint de ação | `var(--primary-tint)` |
| `#dde1f5` (`.ev-back-btn` borda) | borda de ação | `var(--outline)` |
| `#0369a1` (paleta "info" do link-generator/chips UTM) | ação/info | `var(--primary)` |
| `#f0f9ff` (paleta "info") | tint info | `var(--primary-tint)` |
| `#bae6fd`, `#e0f2fe` (bordas/realces da paleta "info") | sem token equivalente | **deixar literal** |

**Tabela de substituição — border-radius:**

| Valor atual | Token |
|---|---|
| `border-radius: 3px` / `4px` / `6px` / `7px` / `8px` / `10px` / `12px` / `14px` / `16px` / `20px` (todas as ocorrências, incluindo cards e ícones grandes) | `var(--radius)` |

Nota: `var(--radius)` é `0.45rem` (~7.2px). Elementos que hoje usam 12–20px ficarão visivelmente menos arredondados — checar no Step de verificação visual.

**Cores explicitamente fora do escopo desta tabela (ficam literais — ver nota geral do documento):** `#3b82f6`, `#22c55e`, `#f59e0b`, `#f43f5e`, `#8b5cf6`, `#ec4899`, `#1d4ed8`, `#dbeafe`, `#93c5fd`, `#60a5fa`, `#be185d`, `#fce7f3`, `#dcfce7`/`#166534`/`#15803d`/`#bbf7d0`/`#f0fdf4`/`#86efac` (painel de resultado do gerador de link — não é tag de status), `#fee2e2`/`#dc2626`/`#fecaca`/`#fef2f2`/`#fca5a5`/`#ef4444`/`#f87171` (exceto os usos tratados na Task 24), `#fef9c3`/`#fde68a`/`#a16207`/`#fef3c7`/`#b45309`, `#1e2235`, `#9097b5`, `#cbd5e1`, `#0c4a6e`, `#e4e7f0`, `#f8f9fc`.

- [ ] **Step 2: Remover o bloco `<style>` da view**

old_string (limites do bloco — o conteúdo integral entre as tags foi movido no Step 1):
```erb
<% title 'Eventos Analytics' %>

<style>
  .ev-page { padding: 24px 28px; min-height: 100vh; }
  @media (max-width: 600px) { .ev-page { padding: 16px; } }
  ...
  .ev-event pre {
    background: #f1f5f9;
    border: 1px solid #e2e8f0;
    border-radius: 6px;
    padding: 12px;
    font-size: 11px;
    overflow: auto;
    margin: 8px 0 0;
    line-height: 1.5;
  }
</style>
```
new_string:
```erb
<% title 'Eventos Analytics' %>
```
(usar as linhas reais 3-883 do arquivo atual como `old_string` completo ao executar — aqui mostramos apenas a âncora inicial e final para localização única.)

- [ ] **Step 3: Registrar a nova folha no manifest**

Arquivo: `app/assets/stylesheets/admin.scss`

old_string:
```scss
 *= require layouts/customers
 *= require_self
```
new_string:
```scss
 *= require layouts/customers
 *= require pages/events
 *= require_self
```

- [ ] **Step 4: Verificar visualmente**

Abrir `/crm/events` (com um cliente selecionado e sem cliente, se possível) em tema claro e escuro. Checar: fundo da página e dos cards (`--bg`), texto de títulos/valores de KPI legível (`--fg`), texto secundário (breadcrumb, subtítulos, labels de KPI) em `--fg-alt`, bordas de cards/tabela/inputs em `--outline`, botão "Filtrar" e badge de contagem ainda legíveis sobre fundo escuro (`--chrome-bg`/`--chrome-fg`), cantos de cards/botões/badges com o novo raio (mais retos que antes — confirmar que não ficou estranho nos elementos grandes como `.ev-empty__icon` 20px→7px e `.ev-funnel-section` 16px→7px). Confirmar que o gradiente escuro do funil e do modal continuam OK (não foram tokenizados).

- [ ] **Step 5: Commit**
```bash
git add app/assets/stylesheets/pages/events.scss app/assets/stylesheets/admin.scss app/views/events/index.html.erb
git commit -m "style(events): extract inline <style> block to pages/events.scss using design tokens"
```

---

### Task 24: Badges de status e indicadores de KPI → `.crm-tag`

**Files:**
- Modify: `app/views/events/index.html.erb:1156-1201` (bloco de KPIs + helper `calc_change`)
- Modify: `app/views/events/index.html.erb:1518-1531` (badges de device/status na tabela de sessões)
- Modify: `app/assets/stylesheets/pages/events.scss` (remover regras agora redundantes: `.ev-kpi__change`, `.ev-kpi__change--up/--down/--neutral`, e o estilo inline verde de "converteu")

**Interfaces:**
- Consumes: `.crm-tag`, `.crm-tag--success`, `.crm-tag--danger`, `.crm-tag--neutral` (componentes já definidos em `app/assets/stylesheets/components/_tag.scss` por outra task do plano).
- Produces: nenhum novo seletor público; `.ev-kpi__change` e suas variantes deixam de existir no HTML e podem ser removidas do CSS.

- [ ] **Step 1: Adicionar helper de variante junto ao `calc_change` existente**

old_string (`app/views/events/index.html.erb:1156-1165`):
```erb
    <%
      def calc_change(current, previous)
        return { value: 0, direction: 'neutral' } if previous.zero?
        change = ((current - previous).to_f / previous * 100).round(1)
        { value: change.abs, direction: change > 0 ? 'up' : (change < 0 ? 'down' : 'neutral') }
      end

      sessions_change = calc_change(@unique_sessions, @prev_unique_sessions)
      checkout_change = calc_change(@counts[:checkout_completed], @prev_counts[:checkout_completed])
    %>
```
new_string:
```erb
    <%
      def calc_change(current, previous)
        return { value: 0, direction: 'neutral' } if previous.zero?
        change = ((current - previous).to_f / previous * 100).round(1)
        { value: change.abs, direction: change > 0 ? 'up' : (change < 0 ? 'down' : 'neutral') }
      end

      def tag_variant_for(direction)
        { 'up' => 'success', 'down' => 'danger', 'neutral' => 'neutral' }[direction] || 'neutral'
      end

      sessions_change = calc_change(@unique_sessions, @prev_unique_sessions)
      checkout_change = calc_change(@counts[:checkout_completed], @prev_counts[:checkout_completed])
    %>
```

- [ ] **Step 2: Trocar as 5 badges de KPI para `.crm-tag`**

old_string (`app/views/events/index.html.erb:1167-1201`, os 5 `<span class="ev-kpi__change ...">`):
```erb
        <span class="ev-kpi__change ev-kpi__change--<%= sessions_change[:direction] %>">
```
new_string:
```erb
        <span class="crm-tag crm-tag--<%= tag_variant_for(sessions_change[:direction]) %>">
```

old_string:
```erb
        <span class="ev-kpi__change ev-kpi__change--<%= checkout_change[:direction] %>">
```
new_string:
```erb
        <span class="crm-tag crm-tag--<%= tag_variant_for(checkout_change[:direction]) %>">
```

old_string (aparece 2×, linhas 1187 e 1199, troca idêntica em ambas):
```erb
        <span class="ev-kpi__change ev-kpi__change--neutral">do total</span>
```
e
```erb
        <span class="ev-kpi__change ev-kpi__change--neutral">no periodo</span>
```
new_string (respectivamente):
```erb
        <span class="crm-tag crm-tag--neutral">do total</span>
```
```erb
        <span class="crm-tag crm-tag--neutral">no periodo</span>
```

old_string (`app/views/events/index.html.erb:1193`):
```erb
        <span class="ev-kpi__change ev-kpi__change--down"><%= @abandoned_rate %>% taxa</span>
```
new_string:
```erb
        <span class="crm-tag crm-tag--danger"><%= @abandoned_rate %>% taxa</span>
```

- [ ] **Step 3: Trocar badge de status "convertido"/"abandonado" e device na tabela de sessões**

old_string (`app/views/events/index.html.erb:1518-1520`):
```erb
                  <td class="center">
                    <span class="ev-badge ev-badge--device"><%= s[:device] %></span>
                  </td>
```
new_string:
```erb
                  <td class="center">
                    <span class="crm-tag crm-tag--neutral"><%= s[:device] %></span>
                  </td>
```

old_string (`app/views/events/index.html.erb:1525-1531`):
```erb
                  <td class="center">
                    <% if s[:abandoned] %>
                      <span class="ev-badge ev-badge--abandoned">nao converteu</span>
                    <% else %>
                      <span class="ev-badge" style="background:#dcfce7; color:#15803d">converteu</span>
                    <% end %>
                  </td>
```
new_string:
```erb
                  <td class="center">
                    <% if s[:abandoned] %>
                      <span class="crm-tag crm-tag--danger">nao converteu</span>
                    <% else %>
                      <span class="crm-tag crm-tag--success">converteu</span>
                    <% end %>
                  </td>
```

- [ ] **Step 4: Remover CSS redundante em `pages/events.scss`**

Remover as regras `.ev-kpi__change`, `.ev-kpi__change--up`, `.ev-kpi__change--down`, `.ev-kpi__change--neutral` e `.ev-badge--device`, `.ev-badge--abandoned` (linhas correspondentes às antigas 396-407 e 775-776 do arquivo original) — agora cobertas por `.crm-tag`. Manter `.ev-badge`, `.ev-badge--mono`, `.ev-badge--page`, `.ev-badge--product`, `.ev-badge--cart`, `.ev-badge--checkout`, `.ev-badge--count`, `.ev-badge--discount` (badges categóricas sem equivalente em `.crm-tag`, ver nota geral do documento).

- [ ] **Step 5: Verificar visualmente**

Nos KPIs do topo, confirmar que os selos de variação (%) usam o verde/vermelho/cinza do `.crm-tag` (levemente diferentes dos tons antigos: `#e6f4ea`/`#1d7a3e` vs `#dcfce7`/`#15803d`). Na tabela "Sessões Recentes", confirmar badges "converteu"/"não converteu"/device com a nova aparência, em claro e escuro (o `.crm-tag--success`/`--danger` usa cores fixas hoje — checar contraste no tema escuro, já que o componente `_tag.scss` fornecido não redefine essas cores para `.theme-dark`).

- [ ] **Step 6: Commit**
```bash
git add app/views/events/index.html.erb app/assets/stylesheets/pages/events.scss
git commit -m "style(events): replace KPI change/status badges with crm-tag component"
```

---

### Task 25: Cores inline dispersas no HTML → tokens

**Files:**
- Modify: `app/views/events/index.html.erb:911-929` (chips de UTM/afiliado no cabeçalho)
- Modify: `app/views/events/index.html.erb:996-1010` (label + botão "Copiar cupom")
- Modify: `app/views/events/index.html.erb:1356-1358` e `:1396-1398` (placeholder "Sem dados")
- Modify: `app/views/events/index.html.erb:1500`, `:1521` (células da tabela de sessões)
- Modify: `app/assets/stylesheets/pages/events.scss` (nova classe `.ev-inline-code`)

**Interfaces:**
- Consumes: `var(--primary)`, `var(--primary-tint)`, `var(--fg)`, `var(--fg-alt)` de `tokens.scss`.
- Produces: classe utilitária `.ev-inline-code` em `pages/events.scss`, reaproveitada nos dois pontos onde o mesmo `<code style="...">` estava duplicado.

- [ ] **Step 1: Criar classe `.ev-inline-code` em `pages/events.scss`**

Adicionar ao final do arquivo:
```scss
.ev-inline-code {
  background: var(--primary-tint);
  color: var(--primary);
  padding: 1px 6px;
  border-radius: 4px;
  font-size: 12px;
  border: 1px solid var(--outline);
}
```
(nota: a borda original era `#bae6fd`, sem token equivalente — usando `var(--outline)` como aproximação neutra; ver decisão pendente no topo do documento.)

- [ ] **Step 2: Substituir os dois `<code style="...">` duplicados**

old_string (aparece 2×, linhas 913 e 923, troca idêntica em ambas):
```erb
        Exibindo eventos com <code style="background:#f0f9ff;color:#0369a1;padding:1px 6px;border-radius:4px;font-size:12px;border:1px solid #bae6fd;">utm_affiliate=<%= @utm_code %></code>
```
new_string:
```erb
        Exibindo eventos com <code class="ev-inline-code">utm_affiliate=<%= @utm_code %></code>
```

- [ ] **Step 3: Label "Cupom de desconto" e botão "Copiar cupom"**

old_string (`app/views/events/index.html.erb:998`):
```erb
              <span style="font-size:11px; color:#64748b;">Cupom de desconto:</span>
```
new_string:
```erb
              <span style="font-size:11px; color:var(--fg-alt);">Cupom de desconto:</span>
```

old_string (`app/views/events/index.html.erb:1003-1010`):
```erb
              <button
                type="button"
                onclick="navigator.clipboard.writeText('<%= @affiliate.discount_code %>').then(function(){ var el = document.getElementById('ev-discount-copy-label'); el.textContent = 'Copiado!'; setTimeout(function(){ el.textContent = 'Copiar cupom'; }, 2000); })"
                style="display:inline-flex;align-items:center;gap:4px;padding:2px 8px;border:1px solid #fde68a;border-radius:4px;background:#fff;color:#a16207;font-size:11px;cursor:pointer;"
              >
```
new_string:
```erb
              <button
                type="button"
                onclick="navigator.clipboard.writeText('<%= @affiliate.discount_code %>').then(function(){ var el = document.getElementById('ev-discount-copy-label'); el.textContent = 'Copiado!'; setTimeout(function(){ el.textContent = 'Copiar cupom'; }, 2000); })"
                style="display:inline-flex;align-items:center;gap:4px;padding:2px 8px;border:1px solid #fde68a;border-radius:4px;background:var(--bg);color:#a16207;font-size:11px;cursor:pointer;"
              >
```
(mantido `#fde68a`/`#a16207` — cor do badge de cupom, categórica, sem token — ver nota geral.)

- [ ] **Step 4: Placeholders "Sem dados" (2 ocorrências idênticas)**

old_string (aparece 2×, linhas 1357 e 1397, troca idêntica em ambas):
```erb
          <p style="color:#94a3b8; font-size:13px; text-align:center; padding:32px 0">Sem dados</p>
```
new_string:
```erb
          <p style="color:var(--fg-alt); font-size:13px; text-align:center; padding:32px 0">Sem dados</p>
```

- [ ] **Step 5: Células de texto da tabela de sessões**

old_string (`app/views/events/index.html.erb:1500`):
```erb
                  <td style="font-weight:500; color:#0f172a"><%= s[:shop_domain] %></td>
```
new_string:
```erb
                  <td style="font-weight:500; color:var(--fg)"><%= s[:shop_domain] %></td>
```

old_string (`app/views/events/index.html.erb:1521`):
```erb
                  <td class="center" style="color:#64748b; font-size:12px"><%= s[:duration_min] %> min</td>
```
new_string:
```erb
                  <td class="center" style="color:var(--fg-alt); font-size:12px"><%= s[:duration_min] %> min</td>
```

- [ ] **Step 6: Verificar visualmente**

Com um afiliado selecionado (`?utm_code=...`), conferir o chip `utm_affiliate=...` no cabeçalho e no subtítulo — mesmo visual em ambos os pontos (agora vindos da mesma classe), com fundo/texto em azul do tema (`--primary`/`--primary-tint`) tanto no claro quanto no escuro. Conferir a coluna "Domínio" e "Duração" da tabela de sessões com o texto no tom certo em ambos os temas. Conferir "Sem dados" nos cards de Top Produtos quando vazios.

- [ ] **Step 7: Commit**
```bash
git add app/views/events/index.html.erb app/assets/stylesheets/pages/events.scss
git commit -m "style(events): tokenize scattered inline colors and dedupe utm code chip markup"
```

---

### Task 26: Botões e inputs → `.crm-btn` / `.crm-input`

**Files:**
- Modify: `app/views/events/index.html.erb:934-976` (botão voltar, filtros de mês/ano, botão "Filtrar")
- Modify: `app/views/events/index.html.erb:1022-1042` (input de URL e botões do gerador de link)
- Modify: `app/assets/stylesheets/pages/events.scss` (remover/reduzir CSS custom de `.ev-back-btn`, `.ev-month-filter__btn`, `.ev-month-filter__select`, `.ev-link-generator__input`, `.ev-link-generator__btn`, `.ev-link-generator__copy-btn`)

**Interfaces:**
- Consumes: `.crm-btn`, `.crm-btn--primary`, `.crm-btn--secondary`, `.crm-input` (componentes definidos em `app/assets/stylesheets/components/_button.scss` e `_input.scss` por outra task do plano).
- Produces: nenhuma interface nova. **Importante:** todos os `id`, `onclick` e seletores JS (`getElementById`, `querySelector`, `.dataset`) referenciados pelos scripts inline nesta view devem ser preservados exatamente — não renomear nem remover atributos `id`/`onclick`, só classes/estilo visual.

- [ ] **Step 1: Botão "Voltar para Afiliados"**

old_string (`app/views/events/index.html.erb:934`):
```erb
      <%= link_to affiliates_path, class: "ev-back-btn" do %>
```
new_string:
```erb
      <%= link_to affiliates_path, class: "crm-btn crm-btn--secondary" do %>
```

Remover a regra `.ev-back-btn` / `.ev-back-btn:hover` de `pages/events.scss` (não é mais usada).

- [ ] **Step 2: Botão "Filtrar" (mês/ano)**

old_string (`app/views/events/index.html.erb:965`):
```erb
        <button type="submit" class="ev-month-filter__btn">
```
new_string:
```erb
        <button type="submit" class="crm-btn crm-btn--primary">
```

Remover `.ev-month-filter__btn` / `.ev-month-filter__btn:hover` de `pages/events.scss`. **Nota de decisão:** isso troca o botão de fundo escuro (`#0f172a`) para azul primário — mudança visual intencional de unificação com o design system; sinalizar para o usuário revisar.

- [ ] **Step 3: Selects de ano/mês**

old_string (`app/views/events/index.html.erb:951`):
```erb
        <select name="year" class="ev-month-filter__select <%= 'ev-month-filter__select--active' if @using_month_filter %>">
```
new_string:
```erb
        <select name="year" class="crm-input ev-month-filter__select <%= 'ev-month-filter__select--active' if @using_month_filter %>">
```

old_string (`app/views/events/index.html.erb:958`):
```erb
        <select name="month" class="ev-month-filter__select <%= 'ev-month-filter__select--active' if @using_month_filter %>">
```
new_string:
```erb
        <select name="month" class="crm-input ev-month-filter__select <%= 'ev-month-filter__select--active' if @using_month_filter %>">
```

Em `pages/events.scss`, reduzir `.ev-month-filter__select` para manter apenas o que `.crm-input` não cobre (largura fixa, seta customizada do `<select>`, estado `--active`):
```scss
.ev-month-filter__select {
  height: 34px;
  padding-right: 28px;
  appearance: none;
  background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='12' fill='none' stroke='%2394a3b8' stroke-width='2' viewBox='0 0 24 24'%3E%3Cpath d='M6 9l6 6 6-6'/%3E%3C/svg%3E");
  background-repeat: no-repeat;
  background-position: right 8px center;
}
.ev-month-filter__select--active { border-color: var(--fg); background-color: var(--bg); color: var(--fg); font-weight: 600; }
```
(remover `border`, `background`, `color`, `font-size`, `font-weight`, `cursor`, `border-radius`, `:focus` que já vêm de `.crm-input`.)

- [ ] **Step 4: Input de URL do gerador de link**

old_string (`app/views/events/index.html.erb:1022-1028`):
```erb
            <input
              type="url"
              id="ev-link-input"
              class="ev-link-generator__input"
              placeholder="https://sualojaexemplo.com.br/produtos/camiseta"
              autocomplete="off"
            />
```
new_string:
```erb
            <input
              type="url"
              id="ev-link-input"
              class="crm-input ev-link-generator__input"
              placeholder="https://sualojaexemplo.com.br/produtos/camiseta"
              autocomplete="off"
            />
```

Em `pages/events.scss`, reduzir `.ev-link-generator__input` para o que é específico (padding extra à esquerda por causa do ícone, fonte monoespaçada):
```scss
.ev-link-generator__input { padding-left: 2.25rem; font-family: monospace; }
.ev-link-generator__input::placeholder { font-family: sans-serif; color: var(--fg-alt); }
```
(remover `width`, `border`, `border-radius`, `font-size`, `color`, `background`, `outline`, `transition`, `:focus` — já cobertos por `.crm-input`.)

- [ ] **Step 5: Botão "Gerar link"**

old_string (`app/views/events/index.html.erb:1030`):
```erb
          <button type="button" id="ev-link-generate-btn" class="ev-link-generator__btn" onclick="evGenerateLink('<%= generate_link_events_path %>', '<%= @utm_code %>')">
```
new_string:
```erb
          <button type="button" id="ev-link-generate-btn" class="crm-btn crm-btn--primary" onclick="evGenerateLink('<%= generate_link_events_path %>', '<%= @utm_code %>')">
```

Remover `.ev-link-generator__btn` / `:hover` de `pages/events.scss`.

- [ ] **Step 6: Botão "Copiar" do link gerado**

old_string (`app/views/events/index.html.erb:1042`):
```erb
            <button type="button" class="ev-link-generator__copy-btn" id="ev-link-copy-btn" onclick="evCopyLink()">
```
new_string:
```erb
            <button type="button" class="crm-btn crm-btn--secondary" id="ev-link-copy-btn" onclick="evCopyLink()">
```

Remover `.ev-link-generator__copy-btn` / `:hover` de `pages/events.scss`. **Atenção:** o JS de `evCopyLink()` (script em `app/views/events/index.html.erb:1116-1135`) altera `copyBtn.style.background`/`copyBtn.style.color` diretamente via `id="ev-link-copy-btn"` — manter esse `id` intacto; o botão continuará funcionando pois o JS seta `style` inline, que tem precedência sobre a classe.

- [ ] **Step 7: Verificar visualmente**

No cabeçalho de Afiliados, conferir o botão "Voltar" com a aparência `.crm-btn--secondary`. Nos filtros de mês/ano, conferir selects com aparência de `.crm-input` + seta customizada, e o botão "Filtrar" agora azul primário. No Gerador de Link, conferir o input de URL, o botão "Gerar link" (primário) e o botão "Copiar" (secundário, incluindo o estado verde pós-clique via JS). Testar em claro e escuro.

- [ ] **Step 8: Commit**
```bash
git add app/views/events/index.html.erb app/assets/stylesheets/pages/events.scss
git commit -m "style(events): reuse crm-btn/crm-input components for form controls"
```

---

### Task 27: Cor inline no template JS do modal + revisão final

**Files:**
- Modify: `app/views/events/index.html.erb:1643-1645` (função `chip()` no `<script>` do modal de sessão)

**Interfaces:**
- Consumes: `var(--fg-alt)` de `tokens.scss`.
- Produces: nenhuma. Apenas troca de valor de cor dentro de uma string JS que já monta HTML via `innerHTML` — sem alteração de lógica/comportamento.

- [ ] **Step 1: Trocar cor hardcoded na função `chip()`**

old_string (`app/views/events/index.html.erb:1643-1645`):
```erb
  function chip(label, value) {
    return '<div class="ev-modal__chip"><span style="color:#94a3b8">' + label + '</span> <strong>' + value + '</strong></div>';
  }
```
new_string:
```erb
  function chip(label, value) {
    return '<div class="ev-modal__chip"><span style="color:var(--fg-alt)">' + label + '</span> <strong>' + value + '</strong></div>';
  }
```

Nota: `var(--fg-alt)` funciona normalmente dentro de um atributo `style` inline gerado via `innerHTML`, pois o navegador resolve custom properties da cascata normalmente — não é necessário nenhum ajuste de JS.

- [ ] **Step 2: Revisão final — checklist completo em claro e escuro**

Em `/crm/events`, com e sem `utm_code`, com e sem cliente selecionado, e no estado vazio (`@empty_state`):
- Header, breadcrumb, filtros de período (Hoje/7/15/30 dias) e filtro de mês/ano.
- Gerador de link de afiliado (input, botão gerar, resultado, botão copiar, cupom, erro).
- 5 KPIs no topo (cores de faixa lateral continuam categóricas/inalteradas; selo de variação agora é `.crm-tag`).
- Funil de conversão (fundo escuro/gradiente inalterado, ícones/barras coloridos inalterados).
- Gráficos ApexCharts (cores inalteradas — não fazem parte deste plano, são configuradas via JS).
- Heatmap de atividade por hora (escala de azul inalterada).
- Tabela "Sessões Recentes" (badges de kind, device, status, hover de linha, linha abandonada).
- Modal de detalhes da sessão (abrir uma linha, conferir chips, timeline de eventos, badges por tipo, botão fechar, `Esc`, clique fora).
- Estado vazio (`@empty_state`).

- [ ] **Step 3: Commit**
```bash
git add app/views/events/index.html.erb
git commit -m "style(events): tokenize inline color in modal chip JS template"
```

---

## Área 3 — Try-On Virtual e Dashboard de Vendas

> **Pré-requisitos:** esta seção assume que `app/assets/stylesheets/tokens.scss` (Task 6) e `app/assets/stylesheets/components/{_button,_input,_table,_card,_tag}.scss` + seus `require` em `admin.scss` (Task 8) do plano `2026-08-09-crm-rename-visual-redesign.md` já foram implementados. Nenhuma delas existe ainda no código hoje — as tasks abaixo tratam isso como dado, conforme instruído.

---

### Task 28: Try-On — extrair `<style>` inline para `pages/try_on.scss`

**Files:**
- Create: `app/assets/stylesheets/pages/try_on.scss`
- Modify: `app/views/try_on/index.html.erb:3-417` (remove o bloco `<style>` inteiro)
- Modify: `app/assets/stylesheets/admin.scss` (adicionar `require pages/try_on` antes de `require_self`)

**Interfaces:**
- Consumes: `--bg`, `--fg`, `--fg-alt`, `--primary`, `--outline` (`tokens.scss`, Task 6 do plano principal).
- Produces: nenhuma classe nova consumida por outras views — `pages/try_on.scss` é específico desta página. As classes `.tryon-*` continuam existindo (não viram `.crm-*`), só passam a usar tokens em vez de hex fixo.

**Tabela de substituição mecânica (valores realmente encontrados em `app/views/try_on/index.html.erb:3-417`):**

| Valor original | Contexto onde aparece | Token |
|---|---|---|
| `#fff` / `#ffffff` como **fundo de superfície** (`.tryon-header` bg, `.tryon-tab.active` bg, `.tryon-card` bg, `.tryon-field__input`/`.tryon-field__select` bg) | fundo neutro claro | `var(--bg)` |
| `#e2e8f0` (bordas: header, card, upload tracejado, campo, spinner, botão secundário) | borda neutra | `var(--outline)` |
| `#0f172a` (texto: título do header, título do card, tab ativa) | texto principal escuro | `var(--fg)` |
| `#334155` (texto: hover de tab, texto de upload, status text) | texto secundário mais escuro | `var(--fg)` |
| `#64748b`, `#94a3b8`, `#475569` (texto/ícones secundários: subtítulo, hint, desc, label, texto de tab inativa, ícone de upload, disabled bg do botão primário) | texto/elemento apagado | `var(--fg-alt)` |
| `#3b82f6`, `#2563eb` (borda de foco de campo, hover de upload, `border-top-color` do spinner, gradiente do botão primário) | azul de ação | `var(--primary)` |

**Valores que permanecem literais (sem token correspondente em `tokens.scss`, decisão explícita — ver nota abaixo):**
- Cores semânticas específicas da página: verde de sucesso (`#22c55e`, `#16a34a`, `#f0fdf4`, `#dcfce7`), vermelho de erro (`#ef4444`, `#dc2626`, `#fef2f2`, `#fecaca`), azul informativo claro (`#0369a1`, `#0c4a6e`, `#f0f9ff`, `#bae6fd`), roxo do badge FASHN.AI (`#8b5cf6`, `#a855f7`), cores dos ícones de card por categoria (`#dbeafe`/`#2563eb` produto, `#fce7f3`/`#db2777` modelo, `#fef3c7`/`#d97706` face). `tokens.scss` não define tokens de sucesso/erro/aviso — só `--primary`. Forçar esses valores em `--primary` mudaria o significado visual (ex.: verde de "concluído" viraria azul).
- `#f1f5f9`, `#f8fafc` (fundos neutros claros usados em tabs container, badges, upload zone) — não equivalem a `var(--outline)` (que é cor de borda, `#e7e8ed`) nem a `var(--bg)` (branco puro); é uma terceira superfície neutra que o design system atual não tokeniza. Mantido literal.
- `#fff` usado como **texto** sobre fundo colorido (badge, botão primário, botão de remover) — não é uma superfície, é texto branco sobre acento; mantido literal.
- `border-radius` (8/10/12/14/16px, 50%) — a página usa uma escala graduada de cantos que não corresponde a `var(--radius)` (`0.45rem` ≈ `7.2px`); forçar um valor único achataria a hierarquia visual atual (cards vs. badges vs. botões). Fora do escopo desta tabela — não solicitado pelo spec de tokens.
- `box-shadow: rgba(0,0,0,...)` — não há token de sombra.
- `font-family` — o bloco `<style>` de `try_on/index` **não define** `font-family` em nenhum seletor (raiz ou não), então não há nada a remover aqui (diferente de outras views que possam ter essa declaração).

- [ ] **Step 1: Criar `app/assets/stylesheets/pages/try_on.scss`**

Mover o conteúdo integral do bloco `<style>` (`app/views/try_on/index.html.erb:3-417`, de `.tryon-page { ... }` até `.tryon-section.active { display: block !important; }`) para o novo arquivo, aplicando as substituições da tabela acima. Valores não listados na tabela permanecem exatamente como estão hoje.

- [ ] **Step 2: Remover o bloco `<style>` de `app/views/try_on/index.html.erb`**

```erb
<%# antes (linhas 1-419) %>
<% title 'Virtual Try-On - FASHN.AI' %>

<style>
  .tryon-page { padding: 24px 28px; min-height: 100vh; }
  ...
  .tryon-section.active { display: block !important; }
</style>

<div class="tryon-page">
```

```erb
<%# depois %>
<% title 'Virtual Try-On - FASHN.AI' %>

<div class="tryon-page">
```

O restante do arquivo (markup a partir de `<div class="tryon-page">` e o `<script>` no final) não muda nesta task.

- [ ] **Step 3: Adicionar o require em `app/assets/stylesheets/admin.scss`**

```scss
# antes (trecho final dos requires, já com tokens/components das Tasks 6/8 do plano principal)
 *= require components/tag
 *= require_self
 */
```

```scss
# depois
 *= require components/tag
 *= require pages/try_on
 *= require_self
 */
```

- [ ] **Step 4: Verificar que o asset compila sem erro**

Run: `bin/rails assets:precompile RAILS_ENV=test 2>&1 | tail -20`
Expected: nenhum erro de compilação SCSS (a sintaxe `var(--token)` é CSS puro, compila sem problema dentro de SCSS).

- [ ] **Step 5: Verificar visualmente `/crm/try_on`, claro e escuro**

Abrir `/crm/try_on` logado como admin (ou usuário com `profile_id == 1`, único perfil com acesso segundo `try_on_controller.rb`).
- Claro: header branco com borda cinza clara, abas com pill ativa branca sobre fundo cinza claro, cards com borda cinza clara, texto de título escuro e texto secundário cinza — visualmente idêntico ao estado antes da migração (só trocou hex por var()).
- Clicar no botão de tema (claro/escuro): fundo do `.tryon-header`/`.tryon-card` deve escurecer (`var(--bg)` → `#121317`), texto deve clarear (`var(--fg)`/`var(--fg-alt)`), bordas devem escurecer (`var(--outline)` → `#2c313a`). As cores semânticas (badge roxo, ícones coloridos por categoria, caixa de sucesso verde, caixa de erro vermelha, caixa informativa azul) **não mudam** com o tema — isso é esperado (documentado acima, sem token de status).
- Testar as 3 abas (Try-On Max, Product to Model, Try-On v1.6), upload de imagem (drag-and-drop e clique), e o spinner de carregamento (borda azul girando) em ambos os temas.

- [ ] **Step 6: Commit**

```bash
git add app/assets/stylesheets/pages/try_on.scss app/views/try_on/index.html.erb app/assets/stylesheets/admin.scss
git commit -m "refactor: migrate try_on inline <style> block to tokens-based pages/try_on.scss"
```

---

### Task 29: Try-On — migrar atributos `style=""` inline com cor para classes em `pages/try_on.scss`

**Files:**
- Modify: `app/assets/stylesheets/pages/try_on.scss` (criado na Task 28 — adicionar 6 classes modificadoras ao final)
- Modify: `app/views/try_on/index.html.erb:444` (badge "E-COMMERCE")
- Modify: `app/views/try_on/index.html.erb:733,734,738` (caixa informativa do v1.6)
- Modify: `app/views/try_on/index.html.erb:876` (botão "Gerar Try-On v1.6")
- Modify: `app/views/try_on/index.html.erb:1280-1291` (função JS `showError`, dentro do `<script>`)

**Interfaces:**
- Consumes: `pages/try_on.scss` (Task 28).
- Produces: nenhum atributo `style="..."` com valor de cor restante em `try_on/index.html.erb` (os `style="font-size: ...px;"` nos `<i>` de ícone **não** são tocados nesta task — são só tamanho, não cor, e são usados de forma tão pervasiva e uniforme que reescrevê-los como classes não muda nada visualmente; fora de escopo por não fazer parte da migração de cor/token).

- [ ] **Step 1: Adicionar classes modificadoras ao final de `app/assets/stylesheets/pages/try_on.scss`**

```scss
/* Variações pontuais que hoje são style="" inline no HTML/JS — cores semânticas
   sem token equivalente (ver nota da Task 28), só movidas para CSS nomeado. */
.tryon-badge--ecommerce {
  background: #dcfce7;
  color: #16a34a;
  font-size: 10px;
  font-weight: 700;
  padding: 2px 6px;
  border-radius: 4px;
  margin-left: 2px;
}

.tryon-info--success { background: #f0fdf4; border-color: #86efac; }
.tryon-info__title--success { color: #16a34a; }
.tryon-info__list--success { color: #14532d; }

.tryon-btn--v16 {
  background: linear-gradient(135deg, #16a34a 0%, #15803d 100%);
}

.tryon-result__empty-icon--danger { background: #fef2f2; color: #ef4444; }
.tryon-result__empty-text--danger { color: #dc2626; }
```

- [ ] **Step 2: Badge "E-COMMERCE" — `app/views/try_on/index.html.erb:444`**

```erb
<%# antes %>
      <span style="background: #dcfce7; color: #16a34a; font-size: 10px; font-weight: 700; padding: 2px 6px; border-radius: 4px; margin-left: 2px;">E-COMMERCE</span>
<%# depois %>
      <span class="tryon-badge--ecommerce">E-COMMERCE</span>
```

- [ ] **Step 3: Caixa informativa do v1.6 — `app/views/try_on/index.html.erb:733-738`**

```erb
<%# antes %>
    <div class="tryon-info" style="background: #f0fdf4; border-color: #86efac;">
      <div class="tryon-info__title" style="color: #16a34a;">
        <i class="fa-solid fa-bolt"></i>
        Try-On v1.6: Rapido e otimizado para e-commerce
      </div>
      <ul class="tryon-info__list" style="color: #14532d;">
<%# depois %>
    <div class="tryon-info tryon-info--success">
      <div class="tryon-info__title tryon-info__title--success">
        <i class="fa-solid fa-bolt"></i>
        Try-On v1.6: Rapido e otimizado para e-commerce
      </div>
      <ul class="tryon-info__list tryon-info__list--success">
```

- [ ] **Step 4: Botão "Gerar Try-On v1.6" — `app/views/try_on/index.html.erb:876`**

```erb
<%# antes %>
      <button class="tryon-btn tryon-btn--primary" id="v16-generate-btn" disabled style="background: linear-gradient(135deg, #16a34a 0%, #15803d 100%);">
<%# depois %>
      <button class="tryon-btn tryon-btn--primary tryon-btn--v16" id="v16-generate-btn" disabled>
```

- [ ] **Step 5: Função `showError` no `<script>` — `app/views/try_on/index.html.erb:1280-1291`**

```erb
<%# antes %>
  function showError(message, resultArea) {
    errorBox.textContent = message;
    errorBox.style.display = 'block';
    resultArea.innerHTML = `
      <div class="tryon-result__empty">
        <div class="tryon-result__empty-icon" style="background: #fef2f2; color: #ef4444;">
          <i class="fa-solid fa-triangle-exclamation" style="font-size: 24px;"></i>
        </div>
        <div style="color: #dc2626;">Erro ao processar. Tente novamente.</div>
      </div>
    `;
  }
<%# depois %>
  function showError(message, resultArea) {
    errorBox.textContent = message;
    errorBox.style.display = 'block';
    resultArea.innerHTML = `
      <div class="tryon-result__empty">
        <div class="tryon-result__empty-icon tryon-result__empty-icon--danger">
          <i class="fa-solid fa-triangle-exclamation" style="font-size: 24px;"></i>
        </div>
        <div class="tryon-result__empty-text--danger">Erro ao processar. Tente novamente.</div>
      </div>
    `;
  }
```

- [ ] **Step 6: Verificar visualmente, claro e escuro**

- Abrir a aba "Try-On v1.6": badge verde "E-COMMERCE" ao lado do nome da aba, caixa informativa verde no topo da seção, botão "Gerar Try-On v1.6" com gradiente verde — devem ficar visualmente idênticos ao estado antes desta task.
- Forçar um erro (ex.: cortar a rede antes de clicar em gerar, ou inspecionar via devtools chamando `showError('teste', document.getElementById('tryon-result-area'))` no console): caixa de erro com ícone vermelho sobre fundo rosa claro e texto vermelho.
- Repetir nos dois temas — **atenção**: como essas cores continuam literais (sem token, decisão da Task 28), o fundo verde claro (`#f0fdf4`) e o fundo rosa claro (`#fef2f2`) vão continuar claros mesmo com o tema escuro ativo, destacando-se sobre o `--bg` escuro. Isso é esperado neste plano — não é uma regressão desta task, é uma limitação pré-existente do conjunto de tokens (sem `--success-bg`/`--danger-bg`).

- [ ] **Step 7: Commit**

```bash
git add app/assets/stylesheets/pages/try_on.scss app/views/try_on/index.html.erb
git commit -m "refactor: move remaining try_on inline style= color attributes to named CSS classes"
```

---

### Task 30: Sales Dashboard — migrar `<style>` inline para `pages/sales_dashboard.scss`, reaproveitando `.crm-kpi-card` e `.crm-btn`

**Files:**
- Create: `app/assets/stylesheets/pages/sales_dashboard.scss`
- Modify: `app/views/sales_dashboard/index.html.erb` (arquivo inteiro, 104 linhas — remove `<style>`, troca classes de KPI e de dois botões)
- Modify: `app/assets/stylesheets/admin.scss` (adicionar `require pages/sales_dashboard` antes de `require_self`)

**Interfaces:**
- Consumes: `--bg`, `--fg`, `--fg-alt`, `--primary`, `--outline` (`tokens.scss`, Task 6) e `.crm-kpi-card`/`.crm-kpi-card__label`/`.crm-kpi-card__value`, `.crm-btn`/`.crm-btn--primary` (`components/_card.scss`, `components/_button.scss`, Task 8 do plano principal).
- Produces: nenhuma classe nova consumida por outras views.

Diferente de `try_on`, esta view é pequena o suficiente para reproduzir o antes/depois completo do CSS.

- [ ] **Step 1: Criar `app/assets/stylesheets/pages/sales_dashboard.scss`**

```scss
<%# antes (app/views/sales_dashboard/index.html.erb:4-22, bloco <style> completo) %>
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
```

```scss
// depois (app/assets/stylesheets/pages/sales_dashboard.scss, arquivo novo)
.sd-page { padding: 24px 28px; min-height: 100vh; }

.sd-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  flex-wrap: wrap;
  gap: 16px;
  margin-bottom: 24px;
  background: var(--primary);
  border-radius: 14px;
  padding: 18px 24px;
}
.sd-header__title { font-size: 20px; font-weight: 800; color: #fff; }
.sd-header__subtitle { font-size: 13px; color: #dbe0ff; }

.sd-month-nav { display: flex; align-items: center; gap: 10px; }
.sd-month-nav__btn { background: #fff; color: var(--primary); border-radius: 8px; padding: 6px 12px; text-decoration: none; font-weight: 600; font-size: 13px; }
.sd-month-nav__label { color: #fff; font-weight: 700; min-width: 140px; text-align: center; }

.sd-tag-filter { margin-bottom: 20px; }
.sd-tag-filter input { border: 1px solid var(--outline); border-radius: 8px; padding: 8px 12px; font-size: 13px; }
.sd-tag-filter .crm-btn { margin-left: 6px; }

.sd-kpi-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 16px; margin-bottom: 24px; }
.sd-kpi__hint { font-size: 12px; color: var(--fg-alt); margin-top: 4px; }

.sd-alert {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  background: #fef3c7;
  color: #92400e;
  border-radius: 10px;
  padding: 14px 18px;
  margin-bottom: 20px;
  font-size: 14px;
}
.sd-alert__btn { background: #92400e; color: #fff; border: none; }
.sd-alert__btn:hover { filter: brightness(0.92); }
```

Notas sobre as decisões desta migração (não são substituições 1:1 de valor, são trocas de estratégia — documentadas para revisão):
- `#3b4adf` (a cor de marca própria do header, botão "Filtrar" e chips de navegação de mês) foi mapeada para `var(--primary)`, unificando com a cor primária do resto do CRM em vez de manter uma segunda cor de marca isolada. Isso muda o tom visualmente (de um azul-violeta `#3b4adf` para o azul `#1967d2`/`#47b0f8` do design system) — é uma decisão de design, não uma equivalência de valor; sinalizar para revisão do usuário se o azul-violeta era intencional como identidade própria do dashboard de vendas.
- `.sd-kpi`/`.sd-kpi__label`/`.sd-kpi__value` foram **removidos** do CSS da página porque as classes HTML correspondentes trocam para `.crm-kpi-card`/`.crm-kpi-card__label`/`.crm-kpi-card__value` (Step 2) — reaproveitando o componente em vez de manter CSS quase-duplicado. Isso muda levemente o raio da borda (12px → `var(--radius)` ≈ 7px) e o padding (18px → `1rem 1.25rem`, ou seja 16px/20px) dos cards de KPI.
- `.sd-tag-filter input` **não** foi trocado para `.crm-input`: `.crm-input` tem `width: 100%`, o que quebraria o layout atual (input e botão lado a lado, sem wrapper com largura controlada) — trocar exigiria alterar a estrutura HTML, fora do escopo autorizado ("só CSS"). Só a cor da borda foi tokenizada.
- O botão "Filtrar" (`.sd-tag-filter button`) passa a reaproveitar `.crm-btn .crm-btn--primary` (Step 3) — igual em forma/cor ao resto do app, sem necessidade de CSS próprio.
- O botão "Sincronizar custos" (`.sd-alert button`) mantém a cor de aviso (`#92400e`/`#fef3c7`), que não tem token equivalente (mesma limitação apontada nas Tasks C-1/C-2 do try_on) — mas passa a reaproveitar a **forma** de `.crm-btn` (padding, radius, display) via `class="crm-btn sd-alert__btn"`, só sobrescrevendo a cor.
- `#dbe0ff` (subtítulo do header) e `#fef3c7`/`#92400e` (alerta) permanecem literais — sem token de aviso/contraste-sobre-cor no `tokens.scss` atual.
- `font-family` — o bloco `<style>` de `sales_dashboard/index` não define `font-family` em nenhum seletor; nada a remover aqui.

- [ ] **Step 2: Trocar classes de KPI em `app/views/sales_dashboard/index.html.erb` (5 ocorrências idênticas do padrão, linhas 69-101)**

Todas as ocorrências de `class="sd-kpi"` → `class="crm-kpi-card"`, `class="sd-kpi__label"` → `class="crm-kpi-card__label"`, `class="sd-kpi__value"` → `class="crm-kpi-card__value"` (o `sd-kpi__hint` permanece igual, só o CSS dele foi tokenizado no Step 1). Exemplo de um dos 5 blocos:

```erb
<%# antes %>
      <div class="sd-kpi">
        <div class="sd-kpi__label">Ticket Médio</div>
        <div class="sd-kpi__value"><%= @metrics[:avg_ticket] ? currency(@metrics[:avg_ticket]) : '—' %></div>
      </div>
<%# depois %>
      <div class="crm-kpi-card">
        <div class="crm-kpi-card__label">Ticket Médio</div>
        <div class="crm-kpi-card__value"><%= @metrics[:avg_ticket] ? currency(@metrics[:avg_ticket]) : '—' %></div>
      </div>
```

Aplicar a mesma troca de `sd-kpi`/`sd-kpi__label`/`sd-kpi__value` → `crm-kpi-card`/`crm-kpi-card__label`/`crm-kpi-card__value` nos outros 4 blocos (Faturamento, Taxa de Conversão, ROAS Faturado, CAC) — o `sd-kpi__hint` interno de cada um não muda de nome.

- [ ] **Step 3: Botão "Filtrar" — `app/views/sales_dashboard/index.html.erb:49`**

```erb
<%# antes %>
        <%= button_tag 'Filtrar' %>
<%# depois %>
        <%= button_tag 'Filtrar', class: 'crm-btn crm-btn--primary' %>
```

- [ ] **Step 4: Botão "Sincronizar custos" — `app/views/sales_dashboard/index.html.erb:63`**

```erb
<%# antes %>
          <%= button_to 'Sincronizar custos', sync_ad_costs_sales_dashboard_path(year: @year, month: @month), method: :post %>
<%# depois %>
          <%= button_to 'Sincronizar custos', sync_ad_costs_sales_dashboard_path(year: @year, month: @month), method: :post, class: 'crm-btn sd-alert__btn' %>
```

- [ ] **Step 5: Remover o bloco `<style>` de `app/views/sales_dashboard/index.html.erb`**

```erb
<%# antes (linhas 1-24) %>
<%# app/views/sales_dashboard/index.html.erb %>
<% title 'Dashboard de Vendas' %>

<style>
  .sd-page { padding: 24px 28px; min-height: 100vh; }
  ...
  .sd-alert button { border: none; background: #92400e; color: #fff; border-radius: 8px; padding: 8px 14px; font-size: 13px; font-weight: 600; cursor: pointer; }
</style>

<div class="sd-page">
```

```erb
<%# depois %>
<%# app/views/sales_dashboard/index.html.erb %>
<% title 'Dashboard de Vendas' %>

<div class="sd-page">
```

- [ ] **Step 6: Adicionar o require em `app/assets/stylesheets/admin.scss`**

```scss
# antes (trecho final dos requires, incluindo pages/try_on da Task 28)
 *= require pages/try_on
 *= require_self
 */
```

```scss
# depois
 *= require pages/try_on
 *= require pages/sales_dashboard
 *= require_self
 */
```

- [ ] **Step 7: Rodar os testes da controller (para garantir que a troca de classes não quebrou nenhuma asserção de HTML)**

Run: `bin/rails test test/controllers/sales_dashboard_controller_test.rb`
Expected: mesmo número de runs/failures/errors de antes desta task (a suíte existente testa comportamento de controller, não classes CSS — não deve ser afetada, mas rodar para confirmar).

- [ ] **Step 8: Verificar visualmente `/crm/vendas`, claro e escuro**

- Claro: header azul (`var(--primary)`) com título/subtítulo brancos, navegação de mês com chips brancos e texto azul, 5 cards de KPI com o mesmo visual de antes (borda e raio ligeiramente menores — conferir se aceitável), botão "Filtrar" no estilo primário padrão do CRM (antes era um botão azul-violeta customizado).
- Se o cliente selecionado não tiver custo de anúncio configurado: caixa de alerta amarela com botão marrom "Sincronizar custos" (visível só para admin) — deve manter a cor de aviso original.
- Alternar para escuro: header muda de tom de azul (`#1967d2` → `#47b0f8`), cards de KPI escurecem (`var(--bg)`/`var(--outline)` escuros), texto dos KPIs clareia. A caixa de alerta amarela **não** escurece (mesma limitação documentada nas tasks do try_on — cor de aviso sem token).
- Navegar entre meses (‹ ›) e aplicar um filtro de tag para confirmar que nada quebrou funcionalmente.

- [ ] **Step 9: Commit**

```bash
git add app/assets/stylesheets/pages/sales_dashboard.scss app/views/sales_dashboard/index.html.erb app/assets/stylesheets/admin.scss
git commit -m "refactor: migrate sales_dashboard to tokens-based CSS, reuse crm-kpi-card and crm-btn components"
```

---

## Área 4 — Operações (Clientes, Consumidores, Pedidos, Produtos)

### Task 31: `clients/index.html.erb`

**Files:**
- Create: `app/assets/stylesheets/pages/clients.scss`
- Modify: `app/views/clients/index.html.erb:1-217` (remove `<style>` block at 150-218, swap classes throughout)
- Modify: `app/assets/stylesheets/admin.scss` (add require)

**Interfaces:**
- Consumes: tokens from `app/assets/stylesheets/tokens.scss` (`--primary`, `--bg`, `--fg`, `--fg-alt`, `--outline`, `--primary-tint`, `--radius`); components `.crm-btn`/`.crm-btn--primary`/`.crm-btn--secondary`, `.crm-table`, `.crm-tag` + variants, `.crm-input`, `.crm-label` from `app/assets/stylesheets/components/*.scss`
- Produces: `app/assets/stylesheets/pages/clients.scss` (new file, also extended by Task 32)

- [ ] **Step 1: Criar `app/assets/stylesheets/pages/clients.scss` com os estilos de `clients/index` migrados para tokens**

O bloco `<style>` (linhas 150-218) tem classes que hoje reimplementam manualmente o que os componentes `.crm-btn`, `.crm-table`, `.crm-tag`, `.crm-input`, `.crm-label` já cobrem. Regra aplicada: onde a classe existente é 1:1 com um componente (botão primário/secundário, tabela, badges de status, input de filtro, label), a classe do componente é adicionada/substituída no ERB e a regra correspondente é **removida** do SCSS. O que sobra no SCSS é só o que é específico da página (wrapper de padding, avatar, badges sem variante semântica clara, paginação).

Decisões que ficaram sem componente equivalente nos tokens fornecidos (fique atento, sinalizado ao usuário no resumo final):
- Não existe variante "success" (verde) nem "danger" (vermelho) de botão em `_button.scss` — o botão "Novo Cliente" (verde) e o botão de excluir (vermelho) continuam com classes de página (`clients-btn--success`, `clients-btn--danger`), mas agora usando `crm-btn` como base e cores fixas próximas às usadas em `.crm-tag--success`/`.crm-tag--danger` para manter coerência visual.
- O contador "Usuários" (badge azul) não é um status (sucesso/erro/aviso/neutro), então não virou `.crm-tag` — ficou como classe de página recolorida com `var(--primary)`/`var(--primary-tint)`.

Conteúdo do novo arquivo:
```scss
.clients-wrapper { padding: 1.5rem 2rem; }

/* ---- Filtros ---- */
.clients-filters {
  background: var(--bg);
  border: 1px solid var(--outline);
  border-radius: var(--radius);
  padding: 1.1rem 1.5rem;
  margin-bottom: 1.5rem;
}
.clients-filters__row { display: flex; flex-wrap: wrap; gap: 0.85rem; align-items: flex-end; }
.clients-filters__field { display: flex; flex-direction: column; gap: 0.3rem; flex: 1; min-width: 200px; }
.clients-filters__field--small { flex: 0 0 150px; min-width: 150px; }
.clients-filters__input--select {
  appearance: none;
  background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='12' fill='none' viewBox='0 0 24 24' stroke='%236a6f71' stroke-width='2'%3E%3Cpath stroke-linecap='round' stroke-linejoin='round' d='M19 9l-7 7-7-7'/%3E%3C/svg%3E");
  background-repeat: no-repeat;
  background-position: right 0.75rem center;
  padding-right: 2rem;
  cursor: pointer;
}
:root.theme-dark .clients-filters__input--select {
  /* SVG embutido via data-URI não herda var() — precisa de uma cópia com o stroke de --fg-alt no dark */
  background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='12' fill='none' viewBox='0 0 24 24' stroke='%23a8acad' stroke-width='2'%3E%3Cpath stroke-linecap='round' stroke-linejoin='round' d='M19 9l-7 7-7-7'/%3E%3C/svg%3E");
}
.clients-filters__actions { display: flex; gap: 0.5rem; align-items: flex-end; }

/* ---- Botões sem variante no design system ---- */
.clients-btn--success { background: #1d7a3e; color: #fff; }
.clients-btn--icon { background: var(--primary-tint); color: var(--primary); border: 1px solid var(--outline); padding: 0.4rem 0.6rem; font-size: 0.82rem; }
.clients-btn--danger { background: #fce8e6; color: #c5221f; border-color: transparent; }
.clients-btn--danger:hover { filter: brightness(.95); }

/* ---- Tabela (wrapper + partes específicas; a tabela em si usa .crm-table) ---- */
.clients-table-wrap { background: var(--bg); border: 1px solid var(--outline); border-radius: var(--radius); overflow: hidden; }
.clients-table-header { display: flex; align-items: center; justify-content: space-between; padding: 1rem 1.5rem; border-bottom: 1px solid var(--outline); }
.clients-table-header__title { display: flex; align-items: center; gap: 0.5rem; font-weight: 600; color: var(--fg); font-size: 0.95rem; }
.clients-table-header__count { font-size: 0.8rem; color: var(--fg-alt); background: var(--primary-tint); padding: 0.25rem 0.65rem; border-radius: 20px; }

.clients-table__client { display: flex; align-items: center; gap: 0.75rem; }
.clients-table__avatar { width: 36px; height: 36px; border-radius: 50%; background: var(--primary); color: #fff; font-size: 0.8rem; font-weight: 700; display: flex; align-items: center; justify-content: center; flex-shrink: 0; }
.clients-table__name { font-weight: 600; color: var(--fg); }
.clients-table__id { font-size: 0.75rem; color: var(--fg-alt); }
.clients-table__email { color: var(--primary); text-decoration: none; font-size: 0.875rem; }
.clients-table__email:hover { text-decoration: underline; }
.clients-table__date { color: var(--fg-alt); font-size: 0.82rem; white-space: nowrap; }
.clients-table__shopify-url { color: var(--primary); text-decoration: none; font-size: 0.82rem; font-family: monospace; }
.clients-table__shopify-url:hover { text-decoration: underline; }
.clients-table__empty-field { color: var(--fg-alt); font-size: 0.875rem; }
.clients-table__users-count { background: var(--primary-tint); color: var(--primary); padding: 0.15rem 0.5rem; border-radius: 20px; font-size: 0.75rem; font-weight: 600; }
.clients-table__actions { display: flex; gap: 0.35rem; justify-content: center; }

/* ---- Paginação (will_paginate) ---- */
.clients-pagination { display: flex; list-style: none; gap: 0.4rem; padding: 1rem 1.5rem; margin: 0; justify-content: center; }
.clients-pagination li a, .clients-pagination li span { display: inline-flex; align-items: center; justify-content: center; min-width: 32px; height: 32px; padding: 0 0.5rem; border-radius: var(--radius); font-size: 0.82rem; font-weight: 500; border: 1px solid var(--outline); color: var(--fg); text-decoration: none; }
.clients-pagination li.current span { background: var(--primary); color: #fff; border-color: var(--primary); }
.clients-pagination li a:hover { background: var(--primary-tint); border-color: var(--primary); }
```

- [ ] **Step 2: Remover o `<style>` inline de `clients/index.html.erb`**

Deletar as linhas 150-218 (todo o bloco `<style>...</style>` no final do arquivo, incluindo a linha `.text-center { text-align: center; }` — essa regra já existe globalmente via Bootstrap/`admin.scss`, não precisa ser recriada).

- [ ] **Step 3: Trocar labels e inputs do filtro pelos componentes `.crm-label`/`.crm-input`**

Before (linhas 9-18):
```erb
        <div class="clients-filters__field">
          <label>Buscar</label>
          <%= text_field_tag :search, params[:search], class: 'clients-filters__input', placeholder: 'Nome ou e-mail...' %>
        </div>
        <div class="clients-filters__field clients-filters__field--small">
          <label>Status</label>
          <%= select_tag :status,
              options_for_select([['Todos', ''], ['Ativos', 'active'], ['Inativos', 'inactive']], params[:status]),
              class: 'clients-filters__input clients-filters__input--select' %>
        </div>
```
After:
```erb
        <div class="clients-filters__field">
          <label class="crm-label">Buscar</label>
          <%= text_field_tag :search, params[:search], class: 'crm-input', placeholder: 'Nome ou e-mail...' %>
        </div>
        <div class="clients-filters__field clients-filters__field--small">
          <label class="crm-label">Status</label>
          <%= select_tag :status,
              options_for_select([['Todos', ''], ['Ativos', 'active'], ['Inativos', 'inactive']], params[:status]),
              class: 'crm-input clients-filters__input--select' %>
        </div>
```

- [ ] **Step 4: Trocar os botões de ação pelos componentes `.crm-btn`**

Before (linha 20): `<%= button_tag class: 'clients-btn clients-btn--primary', name: '' do %>`
After: `<%= button_tag class: 'crm-btn crm-btn--primary', name: '' do %>`

Before (linha 26): `<%= link_to clients_path, class: 'clients-btn clients-btn--secondary' do %>`
After: `<%= link_to clients_path, class: 'crm-btn crm-btn--secondary' do %>`

Before (linha 32): `<%= link_to new_client_path, class: 'clients-btn clients-btn--success' do %>`
After: `<%= link_to new_client_path, class: 'crm-btn clients-btn--success' do %>`

Before (linha 118): `<%= link_to edit_client_path(client), class: 'clients-btn clients-btn--icon' do %>`
After: `<%= link_to edit_client_path(client), class: 'crm-btn clients-btn--icon' do %>`

Before (linha 123): `<%= link_to client_path(client), method: :delete, data: { confirm: 'Tem certeza que deseja excluir este cliente?' }, class: 'clients-btn clients-btn--icon clients-btn--danger' do %>`
After: `<%= link_to client_path(client), method: :delete, data: { confirm: 'Tem certeza que deseja excluir este cliente?' }, class: 'crm-btn clients-btn--icon clients-btn--danger' do %>`

- [ ] **Step 5: Trocar a tabela pelo componente `.crm-table`**

Before (linha 55): `<table class="clients-table">`
After: `<table class="crm-table">`

- [ ] **Step 6: Trocar badges de status pelo componente `.crm-tag`**

Before (linhas 85-89):
```erb
              <% if client.active? %>
                <span class="clients-table__badge clients-table__badge--active">Ativo</span>
              <% else %>
                <span class="clients-table__badge clients-table__badge--inactive">Inativo</span>
              <% end %>
```
After:
```erb
              <% if client.active? %>
                <span class="crm-tag crm-tag--success">Ativo</span>
              <% else %>
                <span class="crm-tag crm-tag--neutral">Inativo</span>
              <% end %>
```

Before (linhas 101-110):
```erb
              <% if client.shopify_access_token.present? %>
                <span class="clients-table__badge clients-table__badge--shopify">
                  <svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75L11.25 15 15 9.75m-3-7.036A11.959 11.959 0 013.598 6 11.99 11.99 0 003 9.749c0 5.592 3.824 10.29 9 11.623 5.176-1.332 9-6.03 9-11.622 0-1.31-.21-2.571-.598-3.751h-.152c-3.196 0-6.1-1.248-8.25-3.285z" />
                  </svg>
                  Configurado
                </span>
              <% else %>
                <span class="clients-table__badge clients-table__badge--pending">Não configurado</span>
              <% end %>
```
After (só a classe do `<span>` muda, SVG e texto ficam iguais):
```erb
              <% if client.shopify_access_token.present? %>
                <span class="crm-tag crm-tag--success">
                  <svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75L11.25 15 15 9.75m-3-7.036A11.959 11.959 0 013.598 6 11.99 11.99 0 003 9.749c0 5.592 3.824 10.29 9 11.623 5.176-1.332 9-6.03 9-11.622 0-1.31-.21-2.571-.598-3.751h-.152c-3.196 0-6.1-1.248-8.25-3.285z" />
                  </svg>
                  Configurado
                </span>
              <% else %>
                <span class="crm-tag crm-tag--warning">Não configurado</span>
              <% end %>
```

- [ ] **Step 7: Adicionar `pages/clients` aos requires de `admin.scss`**

Before (`app/assets/stylesheets/admin.scss`, linhas 19-23):
```
 *= require layouts/chosen
 *= require layouts/products
 *= require layouts/orders
 *= require layouts/customers
 *= require_self
```
After:
```
 *= require layouts/chosen
 *= require layouts/products
 *= require layouts/orders
 *= require layouts/customers
 *= require pages/clients
 *= require_self
```

- [ ] **Step 8: Verificar visualmente**

Acessar `/crm/clients` (index) em claro e escuro (`:root.theme-dark`):
- Filtros: input/select com borda `var(--outline)`, foco azul com halo (`--primary-tint`); botão "Filtrar" azul sólido; "Limpar" outline; "Novo Cliente" verde.
- Tabela: cabeçalho sem fundo cinza forte (só borda inferior), hover de linha com tint azul sutil, badges de status (Ativo/Inativo, Configurado/Não configurado) com cores success/neutral/warning corretas.
- Botões de ação (editar = ícone azul, excluir = ícone vermelho) continuam visíveis e clicáveis.
- Paginação com item atual destacado em `var(--primary)`.
- Confirmar que trocar para tema escuro não deixa nada com fundo branco “vazando” (cards, tabela, paginação todos usando `var(--bg)`/`var(--outline)`).

- [ ] **Step 9: Commit**
```bash
git add app/views/clients/index.html.erb app/assets/stylesheets/pages/clients.scss app/assets/stylesheets/admin.scss
git commit -m "style(clients): migrate clients/index to design tokens and crm-* components"
```

---

### Task 32: `clients/_form.html.erb`

Reusado por `clients/new.html.erb` e `clients/edit.html.erb` (ambos com 1 linha, `<%= render 'form', client: @client, read_only: ... %>` — não precisam de task própria).

**Files:**
- Modify: `app/assets/stylesheets/pages/clients.scss` (criado na Task 31; esta task adiciona a seção do form)
- Modify: `app/views/clients/_form.html.erb:1-361` (remove `<style>` 299-362, swap classes)

**Interfaces:**
- Consumes: mesmos tokens/components da Task 31; assume que `app/assets/stylesheets/pages/clients.scss` já existe (criado na Task 31) e que `*= require pages/clients` já está em `admin.scss`
- Produces: `app/assets/stylesheets/pages/clients.scss` (seção adicional, form)

Decisão sinalizada: as seções "Integração Shopify" (`cform-section--shopify`, verde) e "Integração Zapi" (`cform-section--zapi`, azul) usavam cores decorativas de agrupamento que não fazem parte da paleta de tokens (só existe `--primary` azul, não um verde/azul secundário "de marca"). Para não inventar cores fora do design system, elas foram neutralizadas para `var(--bg)`/`var(--outline)`, perdendo a distinção visual verde/azul entre seções — isso é uma mudança de comportamento visual, não só de cor, então pode valer a pena confirmar com quem aprovar o plano antes de implementar.

- [ ] **Step 1: Adicionar a seção do formulário em `app/assets/stylesheets/pages/clients.scss`**

Anexar ao final do arquivo criado na Task 31:
```scss

/* ============ Formulário (clients/_form) ============ */
.cform-wrapper { padding: 1.5rem 2rem; display: flex; justify-content: center; }
.cform-card { background: var(--bg); border: 1px solid var(--outline); border-radius: var(--radius); width: 100%; overflow: hidden; }

.cform-card__header { display: flex; align-items: center; gap: 1rem; padding: 1.5rem 1.75rem; border-bottom: 1px solid var(--outline); }
.cform-card__header-icon { width: 44px; height: 44px; border-radius: var(--radius); background: var(--primary); color: #fff; display: flex; align-items: center; justify-content: center; flex-shrink: 0; }
.cform-card__title { font-size: 1.05rem; font-weight: 700; color: var(--fg); margin: 0; }
.cform-card__subtitle { font-size: 0.8rem; color: var(--fg-alt); margin: 0.15rem 0 0; }

.cform-errors { display: flex; align-items: flex-start; gap: 0.75rem; padding: 1rem 1.5rem; background: #fce8e6; border-bottom: 1px solid #fce8e6; color: #c5221f; font-size: 0.85rem; }
.cform-errors__icon { flex-shrink: 0; color: #c5221f; }
.cform-errors ul { margin: 0.5rem 0 0 1rem; padding: 0; }
.cform-errors li { margin: 0.25rem 0; }

.cform-card__body { padding: 1.75rem; display: flex; flex-direction: column; gap: 1.5rem; }

.cform-section { background: var(--bg); border: 1px solid var(--outline); border-radius: var(--radius); padding: 1.25rem; display: flex; flex-direction: column; gap: 1rem; }
.cform-section__header { display: flex; align-items: center; gap: 0.5rem; font-weight: 600; font-size: 0.9rem; color: var(--fg); margin-bottom: 0.5rem; }

.cform-row { display: grid; grid-template-columns: 1fr 1fr; gap: 1rem; }
@media (max-width: 520px) { .cform-row { grid-template-columns: 1fr; } }

.cform-field { display: flex; flex-direction: column; gap: 0.35rem; }
.cform-field__input--password { font-family: monospace; }
.cform-field__input-wrapper { display: flex; align-items: center; gap: 0.75rem; }
.cform-field__input-wrapper .crm-input { flex: 1; }
.cform-field__hint { font-size: 0.75rem; color: var(--fg-alt); }

.cform-toggle { display: flex; align-items: center; gap: 0.75rem; }
.cform-toggle__input { width: 18px; height: 18px; accent-color: var(--primary); cursor: pointer; }
.cform-toggle__label { font-size: 0.875rem; color: var(--fg); }

.cform-alert { display: flex; align-items: center; gap: 0.65rem; padding: 0.85rem 1rem; border-radius: var(--radius); font-size: 0.85rem; }
.cform-alert--success { background: #e6f4ea; color: #1d7a3e; }
.cform-alert--warning { background: #fef7e0; color: #b06000; }

.cform-users-list { display: flex; flex-direction: column; gap: 0.5rem; }
.cform-user-item { display: flex; align-items: center; gap: 0.75rem; padding: 0.75rem; background: var(--bg); border: 1px solid var(--outline); border-radius: var(--radius); }
.cform-user-item__avatar { width: 32px; height: 32px; border-radius: 50%; background: var(--primary); color: #fff; font-size: 0.7rem; font-weight: 700; display: flex; align-items: center; justify-content: center; flex-shrink: 0; }
.cform-user-item__info { flex: 1; }
.cform-user-item__name { font-weight: 600; font-size: 0.85rem; color: var(--fg); }
.cform-user-item__email { font-size: 0.75rem; color: var(--fg-alt); }
.cform-user-item__link { color: var(--primary); padding: 0.35rem; border-radius: var(--radius); }
.cform-user-item__link:hover { background: var(--primary-tint); }

.cform-card__footer { display: flex; align-items: center; justify-content: flex-end; gap: 0.75rem; padding: 1.25rem 1.75rem; border-top: 1px solid var(--outline); }
```

Observações do que foi **removido** por já estar coberto por componentes:
- `.cform-field__label` → substituída por `.crm-label` no ERB (Step 2).
- `.cform-field__input` (+ focus/disabled) → substituída por `.crm-input` no ERB (Step 3); `.crm-input` já cobre `:focus`, falta o estado `:disabled` (ver Step 6).
- `.cform-field__badge`/`.cform-field__badge--success` → substituída por `.crm-tag`/`.crm-tag--success` no ERB (Step 5).
- `.cform-btn`/`.cform-btn--primary`/`.cform-btn--secondary` → substituída por `.crm-btn`/`.crm-btn--primary`/`.crm-btn--secondary` no ERB (Step 4).
- `.cform-section--shopify`/`.cform-section--zapi` (e seus `__header--shopify`/`__header--zapi`) → removidas, as seções agora usam o `.cform-section` neutro padrão (ver decisão sinalizada acima).

- [ ] **Step 2: `.crm-input` não define `:disabled` — adicionar no componente da página**

`_input.scss` não trata `:disabled`, mas o form usa `disabled: read_only` em todos os campos. Adicionar ao final da seção de form em `pages/clients.scss`:
```scss
.crm-input:disabled { background: var(--outline); cursor: not-allowed; opacity: .7; }
```
(Isso é específico deste form — outras views do design system que usem `.crm-input` desabilitado herdam o mesmo comportamento, o que é aceitável já que é genérico.)

- [ ] **Step 3: Remover o `<style>` inline**

Deletar as linhas 299-362 (bloco `<style>...</style>` no final do arquivo).

- [ ] **Step 4: Trocar todos os labels do form pelo componente `.crm-label`**

Todas as ocorrências de `class: 'cform-field__label'` nas chamadas `form.label` (linhas 49, 53, 59, 78, 84, 123, 130, 140, 179, 198, 202, 224) trocam para `class: 'crm-label'`. Exemplo (linha 49):

Before: `<%= form.label :name, 'Nome do Cliente', class: 'cform-field__label' %>`
After: `<%= form.label :name, 'Nome do Cliente', class: 'crm-label' %>`

(mesma troca literal `cform-field__label` → `crm-label` nas outras 11 linhas listadas.)

- [ ] **Step 5: Trocar os inputs de texto/email/senha pelo componente `.crm-input`**

Ocorrências de `class: 'cform-field__input'` isolado (linhas 50, 54, 79, 124, 199, 225) trocam para `class: 'crm-input'`. Exemplo (linha 50):

Before: `<%= form.text_field :name, class: 'cform-field__input', required: true, placeholder: 'Nome da empresa ou cliente', disabled: read_only %>`
After: `<%= form.text_field :name, class: 'crm-input', required: true, placeholder: 'Nome da empresa ou cliente', disabled: read_only %>`

Ocorrências de `class: 'cform-field__input cform-field__input--password'` (linhas 86, 132, 142, 204) trocam para `class: 'crm-input cform-field__input--password'` (mantendo o modificador de fonte monoespaçada, que não existe no componente). Exemplo (linha 86):

Before: `<%= form.password_field :shopify_access_token, class: 'cform-field__input cform-field__input--password', placeholder: ..., disabled: read_only, value: '' %>`
After: `<%= form.password_field :shopify_access_token, class: 'crm-input cform-field__input--password', placeholder: ..., disabled: read_only, value: '' %>`

- [ ] **Step 6: Trocar os botões pelo componente `.crm-btn`**

Before (linha 236): `<%= button_to 'Desconectar', client_google_ads_disconnect_path(client), method: :delete, class: 'cform-btn cform-btn--secondary', form: { style: 'margin-left: auto;' } %>`
After: `<%= button_to 'Desconectar', client_google_ads_disconnect_path(client), method: :delete, class: 'crm-btn crm-btn--secondary', form: { style: 'margin-left: auto;' } %>`

Before (linha 239): `<%= link_to 'Conectar Google Ads', client_google_ads_connect_path(client), class: 'cform-btn cform-btn--primary' %>`
After: `<%= link_to 'Conectar Google Ads', client_google_ads_connect_path(client), class: 'crm-btn crm-btn--primary' %>`

Before (linha 277): `<%= link_to clients_path, class: 'cform-btn cform-btn--secondary' do %>`
After: `<%= link_to clients_path, class: 'crm-btn crm-btn--secondary' do %>`

Before (linha 284): `<%= form.button class: 'cform-btn cform-btn--primary', data: { disable_with: client.new_record? ? 'Criando...' : 'Salvando...' } do %>`
After: `<%= form.button class: 'crm-btn crm-btn--primary', data: { disable_with: client.new_record? ? 'Criando...' : 'Salvando...' } do %>`

- [ ] **Step 7: Trocar os selos "Configurado" pelo componente `.crm-tag`**

Ocorrências de `class="cform-field__badge cform-field__badge--success"` (linhas 88, 134, 144, 206) trocam para `class="crm-tag crm-tag--success"`. Exemplo (linha 88):

Before: `<span class="cform-field__badge cform-field__badge--success">Configurado</span>`
After: `<span class="crm-tag crm-tag--success">Configurado</span>`

- [ ] **Step 8: Remover as variantes de cor por seção (Shopify verde / Zapi azul)**

Before (linha 68): `<div class="cform-section cform-section--shopify">`
After: `<div class="cform-section">`

Before (linha 69): `<div class="cform-section__header cform-section__header--shopify">`
After: `<div class="cform-section__header">`

Before (linha 112): `<div class="cform-section cform-section--zapi">`
After: `<div class="cform-section">`

Before (linha 113): `<div class="cform-section__header cform-section__header--zapi">`
After: `<div class="cform-section__header">`

- [ ] **Step 9: Verificar visualmente**

Acessar `/crm/clients/new` e `/crm/clients/:id/edit` em claro e escuro:
- Cabeçalho do card com ícone em fundo `var(--primary)`.
- Todos os campos de texto/senha com aparência `.crm-input` (borda `var(--outline)`, foco azul com halo), campos desabilitados (`read_only`) visivelmente acinzentados.
- Seções (Informações Básicas, Shopify, Zapi, Dashboard, Meta Ads, Google Ads) agora todas com o mesmo fundo neutro — confirmar que ainda dá pra distinguir uma seção da outra pelo título/ícone, já que a cor de fundo diferenciada foi removida.
- Selos "Configurado" em verde (`crm-tag--success`).
- Alertas de sucesso/aviso (Shopify/Zapi configurados ou pendentes) com cores success/warning.
- Botões "Voltar" (secundário) e "Salvar"/"Criar" (primário) com aparência `.crm-btn`.
- Mensagens de erro de validação em vermelho, legíveis em ambos os temas.

- [ ] **Step 10: Commit**
```bash
git add app/views/clients/_form.html.erb app/assets/stylesheets/pages/clients.scss
git commit -m "style(clients): migrate clients/_form to design tokens and crm-* components"
```

---

## Mapeamento hex → token (compartilhado pelas Tasks D-3, D-4, D-5)

`app/assets/stylesheets/layouts/customers.scss`, `layouts/orders.scss` e `layouts/products.scss` **não têm** classes Bootstrap (`btn btn-primary`, `table`, `badge bg-*`, `form-control`) como o enunciado original presumia — são arquivos SCSS dedicados (já com `*= require layouts/customers` etc. em `admin.scss`) cheios de classes BEM hand-rolled (`customers-btn--primary`, `orders-table`, `products-badge--sku`...) com cores em hex fixo, na mesma paleta legada usada nos `<style>` de `clients/index`/`clients/_form` (Tasks D-1/D-2). **Acho que vale confirmar esse ponto com quem for revisar o plano antes de rodar as tasks D-3 a D-5** — o trabalho aqui não é "trocar Bootstrap por crm-*", é migrar essas três folhas de estilo BEM para tokens e, onde a classe já corresponde 1:1 a um componente (botão, tabela, tag, input), trocar para `.crm-*`.

Tabela de conversão usada nas três tasks:

| Hex legado | Token/uso |
|---|---|
| `#3b4adf` (e `#2f3bbf` hover-escurecido) | `var(--primary)` |
| `#eef0fd` | `var(--primary-tint)` |
| `#ffffff` / `#fff` | `var(--bg)` |
| `#1e2235` | `var(--fg)` |
| `#5a6380`, `#9097b5` | `var(--fg-alt)` |
| `#e4e7f0`, `#dde1f5` | `var(--outline)` |
| `#c4c9dd` | `var(--fg-alt)` (texto "vazio"/placeholder) |
| `#f8f9fc`, `#f4f5fb`, `#f0f2fb`, `#f0f2f8` | Depende do contexto: fundo de card/thead/tfoot → remover (transparente / `var(--bg)`, já que `.crm-table`/`.crm-card` não usam fundo cinza); hover de linha/botão quick → `var(--primary-tint)` |
| `box-shadow: 0 1px 4px rgba(0,0,0,0.05)` (nos wrappers de card/tabela/filtros) | Remover — o design system é flat, sem sombra (nenhum componente em `_card.scss`/`_table.scss` usa `box-shadow`) |
| `#1d7a3e` / `#e8f5e9`+`#2e7d32` (verde) | Mantido como cor fixa só onde o significado é "sucesso"/"disponível", alinhado a `.crm-tag--success` |

---

### Task 33: `customers/index.html.erb`

**Files:**
- Modify: `app/views/customers/index.html.erb:1-158` (parte com filtros/tabela; o modal de detalhes de cliente, linhas 160-334, é JS/estrutura funcional e não é tocado além do CSS do próprio modal)
- Modify: `app/assets/stylesheets/layouts/customers.scss:1-339`

**Interfaces:**
- Consumes: tokens (`app/assets/stylesheets/tokens.scss`), componentes `.crm-btn`, `.crm-table`, `.crm-tag`, `.crm-input`, `.crm-label`
- Produces: nenhuma (view + scss de página apenas)

- [ ] **Step 1: Labels e inputs do filtro → `.crm-label`/`.crm-input`**

Before (linhas 10-25):
```erb
        <div class="customers-filters__field">
          <label>Buscar</label>
          <%= text_field_tag :search, params[:search], class: 'customers-filters__input', placeholder: 'Nome ou e-mail...' %>
        </div>
        <div class="customers-filters__field">
          <label>Telefone</label>
          <%= text_field_tag :phone, params[:phone], class: 'customers-filters__input', placeholder: '+55...' %>
        </div>
        <div class="customers-filters__field customers-filters__field--sm">
          <label>Min. de compras</label>
          <%= number_field_tag :min_orders, params[:min_orders], class: 'customers-filters__input', placeholder: 'Ex: 3', min: 1 %>
        </div>
        <div class="customers-filters__field">
          <label>Comprou o produto</label>
          <%= text_field_tag :product_name, params[:product_name], class: 'customers-filters__input', placeholder: 'Nome do produto...' %>
        </div>
```
After:
```erb
        <div class="customers-filters__field">
          <label class="crm-label">Buscar</label>
          <%= text_field_tag :search, params[:search], class: 'crm-input', placeholder: 'Nome ou e-mail...' %>
        </div>
        <div class="customers-filters__field">
          <label class="crm-label">Telefone</label>
          <%= text_field_tag :phone, params[:phone], class: 'crm-input', placeholder: '+55...' %>
        </div>
        <div class="customers-filters__field customers-filters__field--sm">
          <label class="crm-label">Min. de compras</label>
          <%= number_field_tag :min_orders, params[:min_orders], class: 'crm-input', placeholder: 'Ex: 3', min: 1 %>
        </div>
        <div class="customers-filters__field">
          <label class="crm-label">Comprou o produto</label>
          <%= text_field_tag :product_name, params[:product_name], class: 'crm-input', placeholder: 'Nome do produto...' %>
        </div>
```

Before (linha 30, dentro de `customers-filters__quick-label`, mantém a própria classe — não é label de campo, é rótulo de seção, não mexer). Before (linhas 33-35, campo "dias" dentro do combo com botão — mantém `customers-filters__input` como classe adicional porque tem largura/raio de borda customizados para colar com o botão ao lado; troca só a base):

Before:
```erb
            <%= number_field_tag :inactive_days, params[:inactive_days],
                class: "customers-filters__input customers-filters__input--days #{'is-active' if params[:inactive_days].present?}",
                placeholder: 'Dias', min: 1, id: 'inactive_days_field' %>
```
After:
```erb
            <%= number_field_tag :inactive_days, params[:inactive_days],
                class: "crm-input customers-filters__input--days #{'is-active' if params[:inactive_days].present?}",
                placeholder: 'Dias', min: 1, id: 'inactive_days_field' %>
```

- [ ] **Step 2: Botões primário/secundário → `.crm-btn`**

Before (linha 58): `<%= button_tag class: 'customers-btn customers-btn--primary', name: '' do %>`
After: `<%= button_tag class: 'crm-btn crm-btn--primary', name: '' do %>`

Before (linha 71): `<%= link_to customers_path, class: 'customers-btn customers-btn--secondary' do %>`
After: `<%= link_to customers_path, class: 'crm-btn crm-btn--secondary' do %>`

Botões sem variante equivalente no design system (export = verde, quick filters = pill toggle, details = botão pequeno na linha da tabela) ganham `crm-btn` como base e mantêm o modificador de página para a cor/tamanho específicos:

Before (linha 37): `class="customers-btn customers-btn--quick <%= 'customers-btn--quick-active' if params[:inactive_days].present? %>"`
After: `class="crm-btn customers-btn--quick <%= 'customers-btn--quick-active' if params[:inactive_days].present? %>"`

Before (linha 48): `class: "customers-btn customers-btn--quick #{'customers-btn--quick-active' if params[:maderite].present?}"`
After: `class: "crm-btn customers-btn--quick #{'customers-btn--quick-active' if params[:maderite].present?}"`

Before (linha 65): `class: 'customers-btn customers-btn--export'`
After: `class: 'crm-btn customers-btn--export'`

Before (linha 135): `<button class="customers-btn customers-btn--details" onclick="openCustomerModal('<%= customer.id %>')">`
After: `<button class="crm-btn customers-btn--details" onclick="openCustomerModal('<%= customer.id %>')">`

- [ ] **Step 3: Tabela → `.crm-table`**

Before (linha 85): `<table class="customers-table">`
After: `<table class="crm-table">`

- [ ] **Step 4: Badges "vazio" → `.crm-tag--neutral`**

Before (linhas 112-116, e repete idêntico nas linhas 126-128 trocando só o texto):
```erb
                <% if customer.email.present? %>
                  <a href="mailto:<%= customer.email %>" class="customers-link"><%= customer.email %></a>
                <% else %>
                  <span class="customers-badge customers-badge--empty">—</span>
                <% end %>
```
After (mesma troca `customers-badge customers-badge--empty` → `crm-tag crm-tag--neutral` nas duas ocorrências, linhas 115 e 127):
```erb
                <% if customer.email.present? %>
                  <a href="mailto:<%= customer.email %>" class="customers-link"><%= customer.email %></a>
                <% else %>
                  <span class="crm-tag crm-tag--neutral">—</span>
                <% end %>
```

O badge de contagem de pedidos (linha 131, `customers-badge customers-badge--orders`) não é status (sucesso/erro/aviso) — mantém classe de página, só recolorida no scss (Step 6).

- [ ] **Step 5: Reduzir `layouts/customers.scss` — remover regras que hoje duplicam componentes**

Remover do arquivo (cobertas por `.crm-btn`, `.crm-btn--primary`, `.crm-btn--secondary`, `.crm-table`, `.crm-tag`, `.crm-tag--neutral`, `.crm-input`, `.crm-label`):
- Base `.customers-btn { ... }` (linhas 85-97) e `.customers-btn:hover` (linha 98) — o que sobra (`--export`, `--details`, `--quick*`) já vem com `crm-btn` de base via Step 2, só precisa das próprias cores.
- `.customers-btn--primary` (linha 99) e `.customers-btn--secondary` (linha 100).
- `.customers-filters__field label` (linhas 34-40) — vira `.crm-label`.
- `.customers-filters__input` base + `:focus` (linhas 41-51) — vira `.crm-input`.
- `.customers-table { ... }` até `.customers-table tfoot th { ... }` (linhas 138-153) — vira `.crm-table`.
- `.customers-badge--empty` (linha 165) — vira `.crm-tag--neutral`.

- [ ] **Step 6: Retonalizar o restante de `layouts/customers.scss` com tokens**

Aplicar a tabela de conversão da seção compartilhada (topo desta task) a todo o restante do arquivo. Ocorrências mecânicas (mesma troca, texto idêntico em cada linha):

- `#3b4adf` → `var(--primary)` nas linhas 77 (`.customers-filters__input:focus`), 79 (idem), 104, 126, 127, 157, 158, 164, 196, 229, 290, 336
- `#e4e7f0` → `var(--outline)` nas linhas 6, 42, 133, 139, 152, 195, 220, 251, 258, 274, 279, 318, 325
- `#ffffff` → `var(--bg)` nas linhas 5, 101, 132, 203, 305 (as ocorrências em regras já removidas no Step 5 — linhas 51, 99, 127, 128 — não se aplicam mais)
- `#1e2235` → `var(--fg)` nas linhas 46, 156, 237, 251, 266, 293, 333
- `#5a6380` → `var(--fg-alt)` nas linhas 37, 120, 146, 153, 163, 189, 270, 292, 337
- `#9097b5` → `var(--fg-alt)` nas linhas 61, 161, 238, 244, 265, 294, 334, 338
- `#eef0fd` → `var(--primary-tint)` nas linhas 78, 126, 157, 164, 228, 289, 324, 336
- `#dde1f5` → `var(--outline)` nas linhas 100, 105, 118, 310
- `#c4c9dd` → `var(--fg-alt)` na linha 165 (já coberta pelo Step 5, se ainda existir alguma outra ocorrência aplicar aqui também)

Remover `box-shadow: 0 1px 4px rgba(0,0,0,0.05)` de `.customers-filters` (linha 10) e `.customers-table-wrap` (linha 136).

Fundos claros de superfície (`#f8f9fc`, `#f4f5fb`, `#f0f2fb`, `#f0f2f8`) tratar caso a caso:
- `.customers-filters__input { background: #f8f9fc; }` → remover (já cai no `var(--bg)` de `.crm-input`).
- `.customers-table thead tr { background: #f4f5fb; }` e `.customers-table tfoot tr { background: #f4f5fb; }` → removidas junto com o bloco de tabela no Step 5 (`.crm-table` não pinta fundo do cabeçalho).
- `.customers-table tbody tr:hover { background: #f8f9fc; }` → removida junto (hover já vem de `.crm-table tbody tr:hover { background: var(--primary-tint); }`).
- `.customers-btn--quick { background: #f4f5fb; ... }` (linha 119) → `background: transparent; border-color: var(--outline);` (visual "secondary" em repouso).
- `.customers-btn--quick:hover { background: #eef0fd; ... }` (linha 126) → `background: var(--primary-tint);`.
- `.customers-badge--id { background: #f0f2fb; ... }` (linha 163) → `background: var(--outline);`.
- `.cmodal__header`, `.cmodal__info-item`, `.cmodal__order-header`, `.cmodal__order-item` (fundos `#f8f9fc`/`#f4f5fb`/`#ffffff`) → `var(--bg)` para os cards brancos, `var(--outline)` a 40% ou `var(--primary-tint)` para as faixas de destaque (`.cmodal__order-header`, que hoje é `#f4f5fb` com hover `#eef0fd`) → trocar para `background: var(--primary-tint);` direto (remove o estado intermediário, já nasce com o tom de destaque; hover pode escurecer levemente com `filter: brightness(.97)`).

- [ ] **Step 7: Verificar visualmente**

Acessar `/crm/customers` em claro e escuro:
- Filtros com inputs `.crm-input`/labels `.crm-label`, botão "Filtrar" primário, "Exportar XLSX" (verde, mantido), "Limpar" secundário.
- Filtros rápidos (pill "Sem compras há Xd" e "Coleção Maderite") com estado ativo em `var(--primary)`.
- Tabela usando `.crm-table` (cabeçalho sem fundo cinza, hover com tint azul).
- Badges "—" (email/telefone vazios) em cinza neutro; badge de contagem de pedidos ainda com tom azul de marca.
- Botão "Ver detalhes" abre o modal; conferir que o modal (avatar, cards de pedido expansíveis, itens) manteve a hierarquia visual e não ficou tudo branco-sobre-branco no tema escuro.

- [ ] **Step 8: Commit**
```bash
git add app/views/customers/index.html.erb app/assets/stylesheets/layouts/customers.scss
git commit -m "style(customers): migrate customers/index to design tokens and crm-* components"
```

---

### Task 34: `orders/index.html.erb`

**Files:**
- Modify: `app/views/orders/index.html.erb:1-181` (parte com filtros/tabela; modal de detalhes do pedido, linhas 183-310, só tem CSS tocado, não a estrutura/JS)
- Modify: `app/assets/stylesheets/layouts/orders.scss:1-541`

**Interfaces:**
- Consumes: tokens, `.crm-btn`, `.crm-table`, `.crm-tag`, `.crm-input`, `.crm-label`
- Produces: nenhuma

- [ ] **Step 1: Labels e inputs do filtro → `.crm-label`/`.crm-input`**

Before (linhas 8-21):
```erb
      <div class="orders-filters__field">
        <label>Buscar</label>
        <%= text_field_tag :search, params[:search], class: 'orders-filters__input', placeholder: 'Nº do pedido...' %>
      </div>

      <div class="orders-filters__field">
        <label>Data início</label>
        <%= date_field_tag :date_from, params[:date_from], class: 'orders-filters__input' %>
      </div>

      <div class="orders-filters__field">
        <label>Data fim</label>
        <%= date_field_tag :date_to, params[:date_to], class: 'orders-filters__input' %>
      </div>
```
After:
```erb
      <div class="orders-filters__field">
        <label class="crm-label">Buscar</label>
        <%= text_field_tag :search, params[:search], class: 'crm-input', placeholder: 'Nº do pedido...' %>
      </div>

      <div class="orders-filters__field">
        <label class="crm-label">Data início</label>
        <%= date_field_tag :date_from, params[:date_from], class: 'crm-input' %>
      </div>

      <div class="orders-filters__field">
        <label class="crm-label">Data fim</label>
        <%= date_field_tag :date_to, params[:date_to], class: 'crm-input' %>
      </div>
```

- [ ] **Step 2: Botões → `.crm-btn`**

Before (linha 24): `<%= button_tag class: 'orders-btn orders-btn--primary', name: '' do %>`
After: `<%= button_tag class: 'crm-btn crm-btn--primary', name: '' do %>`

Before (linha 37): `<%= link_to orders_path, class: 'orders-btn orders-btn--secondary' do %>`
After: `<%= link_to orders_path, class: 'crm-btn crm-btn--secondary' do %>`

Before (linha 31, export — sem variante equivalente, mantém modificador de página): `class: 'orders-btn orders-btn--export'`
After: `class: 'crm-btn orders-btn--export'`

Before (linha 134, botão "Ver" na linha da tabela): `class="orders-btn-detail"`
After: `class="crm-btn orders-btn-detail"`

Before (linha 192, botão "Ver no Shopify" dentro do modal, já usa `orders-btn orders-btn--primary` com estilo inline de tamanho):
```erb
        <a id="order-modal-shopify-link" href="#" target="_blank" rel="noopener noreferrer" class="orders-btn orders-btn--primary" style="font-size:0.8rem; padding:0.4rem 0.9rem;">
```
After:
```erb
        <a id="order-modal-shopify-link" href="#" target="_blank" rel="noopener noreferrer" class="crm-btn crm-btn--primary" style="font-size:0.8rem; padding:0.4rem 0.9rem;">
```

- [ ] **Step 3: Tabela → `.crm-table`**

Before (linha 49): `<table class="orders-table">`
After: `<table class="crm-table">`

- [ ] **Step 4: Badges "vazio" → `.crm-tag--neutral`**

Ocorrências idênticas de `class="orders-badge orders-badge--empty"` nas linhas 96, 109, 121 (cliente sem nome, telefone vazio, total zerado) trocam para `class="crm-tag crm-tag--neutral"`. Exemplo (linha 96):

Before: `<span class="orders-badge orders-badge--empty">—</span>`
After: `<span class="crm-tag crm-tag--neutral">—</span>`

Badges informativos sem status (`orders-badge--order` no número do pedido, `orders-badge--count` na contagem de itens) não têm variante `.crm-tag` equivalente (não são sucesso/erro/aviso/neutro, são só um chip de marca) — mantêm classe de página, recolorida no Step 6.

- [ ] **Step 5: Reduzir `layouts/orders.scss` — remover regras que hoje duplicam componentes**

Remover:
- `.orders-btn { ... }` base (linhas 60-72) e `:hover` (linha 74) — o que sobrar (`--export`, `orders-btn-detail`) já herda de `crm-btn`.
- `.orders-btn--primary` (linha 76) e `.orders-btn--secondary` (linhas 80-84).
- `.orders-filters__field label` (linhas 27-33) — vira `.crm-label`.
- `.orders-filters__input, .orders-filters__select` base + `:focus` (linhas 35-51) — vira `.crm-input` (mantém `.orders-filters__select` só se algum select ainda precisar de estilo próprio; neste arquivo não há `<select>` em `orders/index`, então essa parte do seletor composto pode ser descartada).
- `.orders-table { ... }` até `.orders-table tfoot th { ... }` (linhas 116-159) — vira `.crm-table`.
- `.orders-badge--empty` (linha 278) — vira `.crm-tag--neutral`.

- [ ] **Step 6: Retonalizar o restante de `layouts/orders.scss` com tokens**

- `#3b4adf` → `var(--primary)` nas linhas 97, 102, 104, 170, 175, 185, 202, 223, 266, 273, 350, 369, 420, 507
- `#e4e7f0` → `var(--outline)` nas linhas 12, 110, 125, 149, 314, 368, 392, 446, 463, 475
- `#ffffff` → `var(--bg)` nas linhas 11, 103, 109 (removidas junto ao Step 5 se dentro de regras deletadas), 176, 298, 445
- `#1e2235` → `var(--fg)` nas linhas 41 (removida no Step 5), 120 (removida no Step 5), 194, 227, 331, 415, 489, 539
- `#5a6380` → `var(--fg-alt)` nas linhas 30 (removida no Step 5), 134 (removida no Step 5), 155, 216, 533
- `#9097b5` → `var(--fg-alt)` nas linhas 180, 244, 250, 324, 340, 361, 410, 431, 494, 524
- `#eef0fd` → `var(--primary-tint)` nas linhas 201, 265, 506
- `#dde1f5` → `var(--outline)` nas linhas 83 (removida no Step 5), 95
- `#c4c9dd` → `var(--fg-alt)` nas linhas 280 (removida no Step 5), 476

Remover `box-shadow` em `.orders-filters` (linha 16) e `.orders-table-wrap` (linha 113), e `box-shadow: 0 20px 60px rgba(0,0,0,0.18)`/`0 2px 10px rgba(59,74,223,0.08)` do modal (linhas 305, 453) — os componentes do design system não usam sombra; manter só o necessário para destacar o modal do fundo (pode ficar sem sombra, apoiado no overlay escurecido).

Fundos de superfície:
- `.orders-filters__input { background: #f8f9fc; }` → removido junto ao Step 5.
- `.orders-table thead tr`/`tfoot tr { background: #f4f5fb; }` → removidos junto ao Step 5.
- `.orders-table tbody tr:hover { background: #f8f9fc; }` → removido junto ao Step 5.
- `.orders-btn-detail { background: #f0f2fb; ... }` (linha 96) → `background: transparent; border-color: var(--outline); color: var(--primary);` — hover (linha 101-105, `background: #3b4adf; color: #fff;`) já é `var(--primary)`/`#fff`, só trocar a cor.
- `.order-modal__header`, `.order-modal__meta` (fundo `#f8f9fc`) → `var(--bg)`.
- `.order-modal__item-qty`, `.order-modal__item-img`/`-placeholder` (fundo `#f0f2fb`) → `var(--outline)` a título de placeholder neutro.

- [ ] **Step 7: Verificar visualmente**

Acessar `/crm/orders` em claro e escuro:
- Filtros (busca + datas) com `.crm-input`; botões Filtrar/Exportar/Limpar com cores corretas.
- Tabela com `.crm-table`; badge do número do pedido e contagem de itens ainda no tom de marca; badges "—" neutros.
- Botão "Ver" abre modal de detalhes do pedido com itens, variantes e subtotal legíveis nos dois temas.
- Link "Ver no Shopify" dentro do modal com aparência de botão primário pequeno.

- [ ] **Step 8: Commit**
```bash
git add app/views/orders/index.html.erb app/assets/stylesheets/layouts/orders.scss
git commit -m "style(orders): migrate orders/index to design tokens and crm-* components"
```

---

### Task 35: `products/index.html.erb`

**Files:**
- Modify: `app/views/products/index.html.erb:1-146`
- Modify: `app/assets/stylesheets/layouts/products.scss:1-216`

**Interfaces:**
- Consumes: tokens, `.crm-btn`, `.crm-table`, `.crm-tag`, `.crm-input`, `.crm-label`
- Produces: nenhuma

- [ ] **Step 1: Labels e inputs/selects do filtro → `.crm-label`/`.crm-input`**

Before (linhas 8-32):
```erb
      <div class="products-filters__field">
        <label>Buscar</label>
        <%= text_field_tag :search, params[:search], class: 'products-filters__input', placeholder: 'Nome do produto ou SKU...' %>
      </div>

      <div class="products-filters__field">
        <label>Fornecedor</label>
        <%= select_tag :vendor,
              options_for_select([['Todos', '']] + @vendors.map { |v| [v, v] }, params[:vendor]),
              class: 'products-filters__select' %>
      </div>

      <div class="products-filters__field">
        <label>Variação 1</label>
        <%= select_tag :option1,
              options_for_select([['Todas', '']] + @option1s.map { |o| [o, o] }, params[:option1]),
              class: 'products-filters__select' %>
      </div>

      <div class="products-filters__field">
        <label>Variação 2</label>
        <%= select_tag :option2,
              options_for_select([['Todas', '']] + @option2s.map { |o| [o, o] }, params[:option2]),
              class: 'products-filters__select' %>
      </div>
```
After:
```erb
      <div class="products-filters__field">
        <label class="crm-label">Buscar</label>
        <%= text_field_tag :search, params[:search], class: 'crm-input', placeholder: 'Nome do produto ou SKU...' %>
      </div>

      <div class="products-filters__field">
        <label class="crm-label">Fornecedor</label>
        <%= select_tag :vendor,
              options_for_select([['Todos', '']] + @vendors.map { |v| [v, v] }, params[:vendor]),
              class: 'crm-input' %>
      </div>

      <div class="products-filters__field">
        <label class="crm-label">Variação 1</label>
        <%= select_tag :option1,
              options_for_select([['Todas', '']] + @option1s.map { |o| [o, o] }, params[:option1]),
              class: 'crm-input' %>
      </div>

      <div class="products-filters__field">
        <label class="crm-label">Variação 2</label>
        <%= select_tag :option2,
              options_for_select([['Todas', '']] + @option2s.map { |o| [o, o] }, params[:option2]),
              class: 'crm-input' %>
      </div>
```

- [ ] **Step 2: Botões → `.crm-btn`**

Before (linha 35): `<%= button_tag class: 'products-btn products-btn--primary', name: '' do %>`
After: `<%= button_tag class: 'crm-btn crm-btn--primary', name: '' do %>`

Before (linha 48): `<%= link_to products_path, class: 'products-btn products-btn--secondary' do %>`
After: `<%= link_to products_path, class: 'crm-btn crm-btn--secondary' do %>`

Before (linha 42, export — sem variante equivalente): `class: 'products-btn products-btn--export'`
After: `class: 'crm-btn products-btn--export'`

- [ ] **Step 3: Tabela → `.crm-table`**

Before (linha 60): `<table class="products-table">`
After: `<table class="crm-table">`

- [ ] **Step 4: Badges → `.crm-tag`**

Badge de SKU e de ID Shopify são chips de marca (sem status), mantêm classe de página. Badges "vazio" e de variação mapeiam para tags semânticas — ocorrências idênticas do padrão "vazio" nas linhas 100 e 107 trocam para `crm-tag crm-tag--neutral`, e o padrão "opção presente" nas linhas 98 e 105 troca para `crm-tag crm-tag--success` (ambas variações usam o mesmo par if/else, então a troca é literal nas duas):

Before (linhas 96-102, repete idêntico nas linhas 103-109 para `option2`):
```erb
              <td class="text-center">
                <% if product.option1.present? %>
                  <span class="products-badge products-badge--option"><%= product.option1 %></span>
                <% else %>
                  <span class="products-badge products-badge--empty">—</span>
                <% end %>
              </td>
```
After:
```erb
              <td class="text-center">
                <% if product.option1.present? %>
                  <span class="crm-tag crm-tag--success"><%= product.option1 %></span>
                <% else %>
                  <span class="crm-tag crm-tag--neutral">—</span>
                <% end %>
              </td>
```

Preço/preço comparativo "vazio" (linhas 114, 121) seguem o mesmo padrão `products-badge products-badge--empty` → `crm-tag crm-tag--neutral`.

- [ ] **Step 5: Reduzir `layouts/products.scss` — remover regras que hoje duplicam componentes**

Remover:
- `.products-btn { ... }` base (linhas 58-70) e `:hover` (linha 72).
- `.products-btn--primary` (linhas 74-77) e `.products-btn--secondary` (linhas 82-86).
- `.products-filters__field label` (linhas 26-32) — vira `.crm-label`.
- `.products-filters__input, .products-filters__select` base + `:focus` (linhas 34-50) — vira `.crm-input`.
- `.products-table { ... }` até `.products-table tfoot th { ... }` (linhas 96-145) — vira `.crm-table`.
- `.products-badge--option` (linhas 201-204) e `.products-badge--empty` (linhas 213-216) — viram `.crm-tag--success`/`.crm-tag--neutral`.

- [ ] **Step 6: Retonalizar o restante de `layouts/products.scss` com tokens**

- `#3b4adf` → `var(--primary)` nas linhas 48 (removida no Step 5), 75 (removida no Step 5), 84 (removida no Step 5), 196
- `#e4e7f0` → `var(--outline)` nas linhas 11, 36 (removida no Step 5), 90, 105, 135, 164
- `#ffffff` → `var(--bg)` nas linhas 10, 49 (removida no Step 5), 76 (removida no Step 5), 79 (removida no Step 5), 89
- `#1e2235` → `var(--fg)` nas linhas 40 (removida no Step 5), 100 (removida no Step 5)
- `#5a6380` → `var(--fg-alt)` nas linhas 29 (removida no Step 5), 114 (removida no Step 5), 141 (removida no Step 5), 208
- `#9097b5` → `var(--fg-alt)` nas linhas 176, 182
- `#eef0fd` → `var(--primary-tint)` na linha 195 (`.products-badge--sku`)
- `#dde1f5` → `var(--outline)` na linha 85 (removida no Step 5)
- `#c4c9dd` → `var(--fg-alt)` na linha 215 (removida no Step 5)

Remover `box-shadow` de `.products-filters` (linha 15) e `.products-table-wrap` (linha 93).

Fundos de superfície:
- `.products-filters__input { background: #f8f9fc; }` → removido junto ao Step 5.
- `.products-table thead tr`/`tfoot tr { background: #f4f5fb; }` e `tbody tr:hover { background: #f8f9fc; }` → removidos junto ao Step 5.
- `.products-table__no-img { background: #f0f2fb; }` (linha 171) → `background: var(--outline);`.
- `.products-badge--id { background: #f0f2fb; }` (linha 207) → `background: var(--outline);`.

- [ ] **Step 7: Verificar visualmente**

Acessar `/crm/products` em claro e escuro:
- Filtros com `.crm-input` (incluindo os três `<select>` de fornecedor/variação — confirmar que o Chosen, se aplicado a algum deles, ainda funciona, já que não alteramos IDs/atributos, só a classe visual do `<select>` original).
- Tabela `.crm-table`; badges de variação em verde quando presentes, "—" neutro quando ausentes; SKU e ID Shopify mantêm o chip de marca.
- Miniatura de produto sem imagem mostra placeholder neutro (não mais azul-claro específico).

- [ ] **Step 8: Commit**
```bash
git add app/views/products/index.html.erb app/assets/stylesheets/layouts/products.scss
git commit -m "style(products): migrate products/index to design tokens and crm-* components"
```

---

## Área 5 — Marketing (Campanhas e Afiliados)

## Grupo E: Marketing (Campanhas e Afiliados)

Migra as 7 views de campanhas/afiliados do CSS inline (`<style>` por view) para SCSS organizado em dois arquivos de página novos:

- `app/assets/stylesheets/pages/campaigns.scss` — usado por `campaigns/index`, `campaigns/show`, `campaigns/_form` (e por extensão `campaigns/new`/`campaigns/edit`, que só renderizam a partial).
- `app/assets/stylesheets/pages/affiliates.scss` — usado por `affiliates/index`, `affiliates/show`, `affiliates/_form` + `affiliates/_form_styles` (e por extensão `affiliates/new`/`affiliates/edit`).

Cada view mantém seu prefixo de classes atual (`campaigns-*`, `campaign-show-*`, `cpform-*`, `affiliates-*`, `aff-*`) como *namespace* de layout específico da página — essas classes já são unicamente escopadas pelo wrapper raiz de cada view, então não há colisão de seletor ao concatenar os dois arquivos no mesmo bundle (`admin.scss`). Onde um elemento é um caso 1:1 de um componente já pronto (botão, input+label, tabela, badge/tag), a task troca a classe para o componente compartilhado (`crm-btn`, `crm-input`, `crm-label`, `crm-table`, `crm-tag`) em vez de recriar o mesmo visual com uma classe local — isso também permite **remover** da folha migrada as regras que o componente já cobre (padding/radius/hover de botão, th/td de tabela, etc.), reduzindo o CSS bespoke. Variantes que os componentes não cobrem (ex.: botão de ícone, botão "success", badge azul/"info") viram modificadores locais **encadeados** com a classe do componente (ex.: `class="crm-btn campaigns-btn--icon"`) — a classe local só define cor/borda, o componente já dá forma/tamanho/hover base.

Para `campaigns/show` e `affiliates/show` (blocos grandes, ~116 e ~181 linhas) a task segue a regra simplificada do enunciado: **mover o conteúdo do `<style>` para o novo arquivo aplicando a tabela de substituição de valores abaixo, sem renomear classes nem trocar markup por componentes** — é migração de valor fixo → token, não uma reescrita estrutural. Isso é intencional e está anotado em cada task.

### Tabela de substituição (valor fixo → token) — usada em todas as tasks deste grupo

| Valor(es) original(is) | Novo valor |
|---|---|
| `#fff`, `#ffffff` | `var(--bg)` |
| `#1e2235`, `#3a4060`, `#0f172a`, `#334155` (texto principal) | `var(--fg)` |
| `#9097b5`, `#5a6380`, `#6b7280`, `#64748b`, `#94a3b8`, `#475569` (texto secundário/label) | `var(--fg-alt)` |
| `#e4e7f0`, `#e2e8f0`, `#dde1f5` (bordas 1px) | `var(--outline)` |
| `#f0f2f8`, `#f1f5f9` — **quando usado como borda** | `var(--outline)` |
| `#f0f2f8`, `#f1f5f9`, `#f8f9fc`, `#f8fafc`, `#f0f2fb`, `#f4f5fb` — **quando usado como background** (hover, painel sutil, chip de contagem) | `var(--primary-tint)` |
| `#3b4adf` (cor de marca/link/botão primário) | `var(--primary)` |
| `#eff6ff`, `#dbeafe`, `#f0f9ff`, `#bae6fd` (fundo azul claro informativo) | `var(--primary-tint)` |
| `#1d4ed8`, `#0369a1`, `#3b82f6` (texto/ícone azul informativo) | `var(--primary)` |
| `#d1fae5` / `#065f46` (badge sucesso) | `#e6f4ea` / `#1d7a3e` (paleta `.crm-tag--success`) |
| `#fef2f2` / `#dc2626` / `#991b1b` / `#b91c1c` / `#fecaca` (alerta/badge de erro) | `#fce8e6` / `#c5221f` (paleta `.crm-tag--danger`; hover mais escuro `#a3170f`) |
| `#fef3c7` / `#92400e` / `#fef9c3` / `#a16207` (badge aviso/cupom) | `#fef7e0` / `#b06000` (paleta `.crm-tag--warning`) |
| `#f3f4f6` / `#6b7280` (badge neutro/finalizado) | `var(--outline)` / `var(--fg-alt)` (paleta `.crm-tag--neutral`) |
| raio 6px/7px/8px/10px/12px/14px em cards, inputs, botões, wrappers | `var(--radius)` |
| raio 20px em badges/pills | `999px` (padrão do `.crm-tag`) |
| `#10b981` (ponto pulsante de status "em execução") | mantém (cor decorativa, sem token equivalente) |
| gradiente de avatar `#3b4adf → #6674f5` | `var(--primary) → #6674f5` (só o primeiro stop tem token) |

Valores não listados permanecem como estão (box-shadows, `@keyframes`, `font-family: monospace`, cores de dado (funil, heatmap) que são paletas intencionalmente multicoloridas e não fazem parte do design system).

---

### Task 36: `campaigns/index.html.erb` → `pages/campaigns.scss` (criação)

**Files:**
- Modify: `app/views/campaigns/index.html.erb:1-276`
- Create: `app/assets/stylesheets/pages/campaigns.scss`
- Modify: `app/assets/stylesheets/admin.scss` (adicionar `require pages/campaigns`)

**Interfaces:**
- Consumes: tokens (`var(--*)`), `.crm-btn`/`.crm-btn--primary`/`.crm-btn--secondary`, `.crm-input`, `.crm-label`, `.crm-table`, `.crm-tag`/`.crm-tag--success`/`--danger`/`--warning`/`--neutral` (componentes já definidos em outra task).
- Produces: `.crm-tag--info` (classe já disponível globalmente desde a Task 8, reaproveitada também em `pages/affiliates.scss` na Task 39), `.campaigns-btn--success`/`--icon`/`--danger` (modificadores locais encadeados com `crm-btn`), demais classes `campaigns-*` de layout específico da página.

- [ ] **Step 1: Trocar botões por `.crm-btn`**

Todos em `app/views/campaigns/index.html.erb`:

```erb
# linha 42, antes
<%= button_tag class: 'campaigns-btn campaigns-btn--primary', name: '' do %>
# depois
<%= button_tag class: 'crm-btn crm-btn--primary', name: '' do %>
```
```erb
# linha 48, antes
<%= link_to campaigns_path, class: 'campaigns-btn campaigns-btn--secondary' do %>
# depois
<%= link_to campaigns_path, class: 'crm-btn crm-btn--secondary' do %>
```
```erb
# linha 54, antes
<%= link_to new_campaign_path, class: 'campaigns-btn campaigns-btn--success' do %>
# depois
<%= link_to new_campaign_path, class: 'crm-btn campaigns-btn--success' do %>
```
```erb
# linha 143, antes
<%= link_to edit_campaign_path(campaign), class: 'campaigns-btn campaigns-btn--icon' do %>
# depois
<%= link_to edit_campaign_path(campaign), class: 'crm-btn campaigns-btn--icon' do %>
```
```erb
# linha 148, antes
<%= link_to campaign_path(campaign), method: :delete, data: { confirm: 'Tem certeza que deseja excluir esta campanha?' }, class: 'campaigns-btn campaigns-btn--icon campaigns-btn--danger' do %>
# depois
<%= link_to campaign_path(campaign), method: :delete, data: { confirm: 'Tem certeza que deseja excluir esta campanha?' }, class: 'crm-btn campaigns-btn--icon campaigns-btn--danger' do %>
```
```erb
# linha 165, antes
<%= link_to new_campaign_path, class: 'campaigns-btn campaigns-btn--primary' do %>
# depois
<%= link_to new_campaign_path, class: 'crm-btn crm-btn--primary' do %>
```

- [ ] **Step 2: Trocar labels e inputs do filtro por `.crm-label`/`.crm-input`**

```erb
# linhas 26,30,36 antes (3 ocorrências idênticas na estrutura, texto diferente)
<label>Buscar</label>
<label>Status</label>
<label>Tipo</label>
# depois
<label class="crm-label">Buscar</label>
<label class="crm-label">Status</label>
<label class="crm-label">Tipo</label>
```
```erb
# linha 27, antes
<%= text_field_tag :search, params[:search], class: 'campaigns-filters__input', placeholder: 'Nome da campanha...' %>
# depois
<%= text_field_tag :search, params[:search], class: 'crm-input', placeholder: 'Nome da campanha...' %>
```
```erb
# linhas 31-33, antes
<%= select_tag :status,
    options_for_select([['Todos', ''], ['Ativos', 'active'], ['Inativos', 'inactive'], ['Em execução', 'running']], params[:status]),
    class: 'campaigns-filters__input campaigns-filters__input--select' %>
# depois
<%= select_tag :status,
    options_for_select([['Todos', ''], ['Ativos', 'active'], ['Inativos', 'inactive'], ['Em execução', 'running']], params[:status]),
    class: 'crm-input campaigns-filters__input--select' %>
```
```erb
# linhas 37-39, antes
<%= select_tag :kind,
    options_for_select([['Todos', ''], ['Cashback', 'cashback']], params[:kind]),
    class: 'campaigns-filters__input campaigns-filters__input--select' %>
# depois
<%= select_tag :kind,
    options_for_select([['Todos', ''], ['Cashback', 'cashback']], params[:kind]),
    class: 'crm-input campaigns-filters__input--select' %>
```

(`campaigns-filters__input--select` continua existindo só para a seta customizada do `<select>`, ver Step 5.)

- [ ] **Step 3: Trocar a tabela principal por `.crm-table`**

```erb
# linha 88, antes
<table class="campaigns-table">
# depois
<table class="crm-table">
```

- [ ] **Step 4: Trocar badges/status por `.crm-tag`**

```erb
# linhas 69-73, antes
<% if current_client.zapi_configured? %>
  <span class="campaigns-client-info__badge campaigns-client-info__badge--success">Zapi Configurado</span>
<% else %>
  <span class="campaigns-client-info__badge campaigns-client-info__badge--danger">Zapi Pendente</span>
<% end %>
# depois
<% if current_client.zapi_configured? %>
  <span class="crm-tag crm-tag--success">Zapi Configurado</span>
<% else %>
  <span class="crm-tag crm-tag--danger">Zapi Pendente</span>
<% end %>
```
```erb
# linha 109, antes
<span class="campaigns-table__badge campaigns-table__badge--kind">
# depois
<span class="crm-tag crm-tag--warning">
```
```erb
# linhas 127-139, antes
<% case campaign.status %>
<% when :running %>
  <span class="campaigns-table__status campaigns-table__status--running">
    <span class="campaigns-table__status-dot"></span>
    Em execução
  </span>
<% when :pending %>
  <span class="campaigns-table__status campaigns-table__status--pending">Aguardando</span>
<% when :finished %>
  <span class="campaigns-table__status campaigns-table__status--finished">Finalizada</span>
<% when :inactive %>
  <span class="campaigns-table__status campaigns-table__status--inactive">Inativa</span>
<% end %>
# depois
<% case campaign.status %>
<% when :running %>
  <span class="crm-tag crm-tag--success">
    <span class="campaigns-table__status-dot"></span>
    Em execução
  </span>
<% when :pending %>
  <span class="crm-tag crm-tag--info">Aguardando</span>
<% when :finished %>
  <span class="crm-tag crm-tag--neutral">Finalizada</span>
<% when :inactive %>
  <span class="crm-tag crm-tag--danger">Inativa</span>
<% end %>
```

- [ ] **Step 5: Remover o `<style>` inline (linhas 187-276) e criar `app/assets/stylesheets/pages/campaigns.scss`**

Deletar todo o bloco `<style>...</style>` (linhas 187-276) de `campaigns/index.html.erb`. Criar o arquivo com este conteúdo (seção inicial — as próximas tasks acrescentam mais seções abaixo dela):

```scss
// ===== campaigns/index =====
.campaigns-wrapper { padding: 1.5rem 2rem; }

.campaigns-alert { display: flex; align-items: flex-start; gap: 1rem; padding: 1.25rem 1.5rem; border-radius: var(--radius); margin-bottom: 1.5rem; }
.campaigns-alert--danger { background: #fce8e6; border: 1px solid #f6b3ae; }
.campaigns-alert__icon { flex-shrink: 0; color: #c5221f; }
.campaigns-alert__content { flex: 1; }
.campaigns-alert__content strong { display: block; color: #c5221f; font-size: 0.95rem; margin-bottom: 0.25rem; }
.campaigns-alert__content p { color: #c5221f; font-size: 0.85rem; margin: 0 0 0.75rem; }
.campaigns-alert__link { display: inline-flex; align-items: center; gap: 0.35rem; background: #c5221f; color: #fff; padding: 0.4rem 0.85rem; border-radius: var(--radius); font-size: 0.8rem; font-weight: 500; text-decoration: none; }
.campaigns-alert__link:hover { background: #a3170f; }

.campaigns-client-info { display: flex; align-items: center; gap: 0.75rem; padding: 0.85rem 1.25rem; background: var(--primary-tint); border: 1px solid var(--outline); border-radius: var(--radius); margin-bottom: 1.5rem; }
.campaigns-client-info__label { font-size: 0.8rem; color: var(--fg-alt); }
.campaigns-client-info__name { font-weight: 600; color: var(--fg); }

.campaigns-filters {
  background: var(--bg);
  border: 1px solid var(--outline);
  border-radius: var(--radius);
  padding: 1.1rem 1.5rem;
  margin-bottom: 1.5rem;
  box-shadow: 0 1px 4px rgba(0,0,0,0.05);
}
.campaigns-filters__row { display: flex; flex-wrap: wrap; gap: 0.85rem; align-items: flex-end; }
.campaigns-filters__field { display: flex; flex-direction: column; gap: 0.3rem; flex: 1; min-width: 180px; }
.campaigns-filters__field--small { flex: 0 0 140px; min-width: 140px; }
.campaigns-filters__input--select {
  appearance: none;
  background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='12' fill='none' viewBox='0 0 24 24' stroke='%236a6f71' stroke-width='2'%3E%3Cpath stroke-linecap='round' stroke-linejoin='round' d='M19 9l-7 7-7-7'/%3E%3C/svg%3E");
  background-repeat: no-repeat;
  background-position: right 0.75rem center;
  padding-right: 2rem;
  cursor: pointer;
}
.campaigns-filters__actions { display: flex; gap: 0.5rem; align-items: flex-end; }

// Modificadores locais de crm-btn (variantes que o componente não cobre)
.campaigns-btn--success { background: #1d7a3e; color: #fff; }
.campaigns-btn--icon { padding: 0.4rem 0.6rem; font-size: 0.82rem; }
.campaigns-btn--danger { color: #c5221f; border-color: #f6b3ae; background: #fce8e6; }
.campaigns-btn--danger:hover { background: #f9d3ce; }

// Extensão local de crm-tag (variante "info" azul, não coberta pelo componente)

.campaigns-table-wrap { background: var(--bg); border: 1px solid var(--outline); border-radius: var(--radius); box-shadow: 0 1px 4px rgba(0,0,0,0.05); overflow: hidden; }
.campaigns-table-header { display: flex; align-items: center; justify-content: space-between; padding: 1rem 1.5rem; border-bottom: 1px solid var(--outline); }
.campaigns-table-header__title { display: flex; align-items: center; gap: 0.5rem; font-weight: 600; color: var(--fg); font-size: 0.95rem; }
.campaigns-table-header__count { font-size: 0.8rem; color: var(--fg-alt); background: var(--primary-tint); padding: 0.25rem 0.65rem; border-radius: 999px; }

.campaigns-table-wrap .crm-table tfoot td { padding: 0.75rem 1.25rem; font-size: 0.8rem; color: var(--fg-alt); }

.campaigns-table__id { font-size: 0.75rem; color: var(--fg-alt); }
.campaigns-table__days { font-weight: 500; color: var(--primary); }
.campaigns-table__period { display: flex; flex-direction: column; gap: 0.1rem; font-size: 0.82rem; }
.campaigns-table__period-separator { color: var(--fg-alt); font-size: 0.7rem; }

.campaigns-table__status-dot { width: 6px; height: 6px; border-radius: 50%; background: #10b981; animation: campaigns-pulse 2s infinite; }
@keyframes campaigns-pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.5; } }

.campaigns-table__actions { display: flex; gap: 0.35rem; justify-content: center; }

.campaigns-table__empty { text-align: center; padding: 3rem !important; }
.campaigns-table__empty-content { display: flex; flex-direction: column; align-items: center; gap: 1rem; color: var(--fg-alt); }
.campaigns-table__empty-content svg { opacity: 0.5; }
.campaigns-table__empty-content p { margin: 0; }

.campaigns-pagination { display: flex; list-style: none; gap: 0.4rem; padding: 1rem 1.5rem; margin: 0; justify-content: center; }
.campaigns-pagination li a, .campaigns-pagination li span { display: inline-flex; align-items: center; justify-content: center; min-width: 32px; height: 32px; padding: 0 0.5rem; border-radius: var(--radius); font-size: 0.82rem; font-weight: 500; border: 1px solid var(--outline); color: var(--fg); text-decoration: none; transition: all 0.15s; }
.campaigns-pagination li.current span { background: var(--primary); color: #fff; border-color: var(--primary); }
.campaigns-pagination li a:hover { background: var(--primary-tint); border-color: var(--primary); }
.text-center { text-align: center; }
```

Notas sobre o que foi descartado nesta migração (porque `.crm-table`/`.crm-btn` já cobrem): as regras antigas de `thead th`, `tbody td`, `tbody tr:hover td`, `tfoot td` (exceto padding do tfoot, mantido acima), o `.campaigns-table__campaign {}` vazio, e o padding/radius/hover base de `.campaigns-btn` (agora vem de `.crm-btn`).

- [ ] **Step 6: Adicionar o require em `app/assets/stylesheets/admin.scss`**

```scss
# antes
 *= require layouts/customers
 *= require_self
```
```scss
# depois
 *= require layouts/customers
 *= require pages/campaigns
 *= require pages/affiliates
 *= require_self
```

(O require de `pages/affiliates` é adicionado aqui mesmo — antes de o arquivo existir de fato — porque a Task 39 só vai *criar* `pages/affiliates.scss`; deixar as duas linhas juntas evita um segundo diff no mesmo trecho de `admin.scss`. Sprockets não falha por o arquivo ainda não existir só quando a Task 39 anda em paralelo/depois no mesmo branch — se as tasks forem aplicadas fora de ordem, mova esta linha para a Task 39.)

- [ ] **Step 7: Verificar visualmente**

Abrir `/crm/campaigns` (index). Claro: alerta vermelho de Zapi (se não configurado) com botão "Configurar Zapi"; barra de filtros com inputs/labels no novo estilo; botões "Filtrar" (primário azul), "Limpar" (secundário outline) e "Nova Campanha" (verde); tabela com cabeçalho uppercase cinza, hover azul claro nas linhas; badges de tipo (âmbar), status (verde "Em execução" com ponto pulsante, azul "Aguardando", cinza "Finalizada", vermelho "Inativa"); paginação. Escuro: alternar o tema e confirmar que fundo/texto/bordas trocam (wrapper, filtros, tabela, paginação) e que os badges/alertas mantêm contraste legível (eles usam cores literais fixas, não tokens, então não mudam de tom — só o entorno muda).

- [ ] **Step 8: Commit**

```bash
git add app/views/campaigns/index.html.erb app/assets/stylesheets/pages/campaigns.scss app/assets/stylesheets/admin.scss
git commit -m "style: migrate campaigns#index to token-based design system"
```

---

### Task 37: `campaigns/show.html.erb` → `pages/campaigns.scss` (seção show)

**Files:**
- Modify: `app/views/campaigns/show.html.erb:298-414` (remove o `<style>`)
- Modify: `app/assets/stylesheets/pages/campaigns.scss` (acrescenta seção `campaigns/show`, arquivo já criado pela Task 36)

**Interfaces:**
- Consumes: tokens (`var(--*)`). Esta task **não troca classes por componentes** — segue a regra do bloco grande: move o `<style>` inteiro e aplica a tabela de substituição de valores, mantendo as classes `campaign-show-*` como estão.
- Produces: seção `campaigns/show` em `pages/campaigns.scss`.

- [ ] **Step 1: Remover o `<style>` inline (linhas 298-414) de `campaigns/show.html.erb`**

Manter tudo o resto do arquivo intocado (o `<script>` de linhas 416-430 continua no view, ele controla o modal `#messageModal`/`#messageContent` via `getElementById` e a classe `.open` — nada disso muda).

- [ ] **Step 2: Mover o conteúdo para `pages/campaigns.scss`, seção `campaigns/show`**

Ler o bloco original em `app/views/campaigns/show.html.erb:298-414` e colar seu conteúdo integral ao final de `pages/campaigns.scss` (após a seção `campaigns/index` da Task 36), sob um comentário `// ===== campaigns/show =====`, aplicando a tabela de substituição de valores fixos → tokens do topo deste documento em toda regra. Pontos específicos desta folha (além da tabela genérica):

- Todos os `background`/`border`/`color` em `#fff`, `#e4e7f0`, `#f0f2f8`, `#1e2235`, `#3a4060`, `#9097b5` seguem a tabela genérica (`var(--bg)`, `var(--outline)`, `var(--fg)`, `var(--fg-alt)`).
- `.campaign-show-header__back` (fundo `#f0f2fb`/cor `#3b4adf`) → `var(--primary-tint)` / `var(--primary)`; hover `#e0e4f8` → um tom levemente mais forte, use `color-mix(in srgb, var(--primary-tint) 60%, var(--primary) 10%)` **ou**, mais simples e determinístico, apenas `var(--primary-tint)` com `filter: brightness(.95)` no hover — escolha a segunda opção para não depender de `color-mix`.
- `.campaign-show-alert--danger` e os 4 ícones/badges de status (`--total`/`--sent`/`--pending`/`--failed`, `--running`/`--pending`/`--finished`/`--inactive`) mapeiam para a paleta de tags da tabela genérica: sucesso `#e6f4ea`/`#1d7a3e`, aviso `#fef7e0`/`#b06000`, erro `#fce8e6`/`#c5221f`, neutro `var(--outline)`/`var(--fg-alt)`, informativo (azul "Aguardando"/total) `var(--primary-tint)`/`var(--primary)`.
- `.campaign-show-table__avatar` gradiente `linear-gradient(135deg, #3b4adf, #6674f5)` → `linear-gradient(135deg, var(--primary), #6674f5)` (segundo stop permanece literal, sem token equivalente).
- `.campaign-show-table__status--*` (pending/sent/failed/cancelled) seguem a mesma paleta de tags acima (aviso/sucesso/erro/neutro).
- `.campaign-show-modal__content` (`background: #fff`) → `var(--bg)`; `box-shadow` permanece; `.campaign-show-modal__close:hover` (`background: #f0f2f8`) → `var(--primary-tint)` (é um hover interativo, não uma borda — ver nota na tabela genérica sobre `#f0f2f8` em contexto de background).
- `@keyframes modalIn` e `.campaign-show-modal__backdrop { background: rgba(0,0,0,0.4) }` permanecem literais (sem token para overlay/scrim).
- Todos os `border-radius: 6px/8px/10px/12px` → `var(--radius)`; `border-radius: 20px` em badges → `999px`.

- [ ] **Step 3: Verificar visualmente**

Abrir `/crm/campaigns/:id`. Claro: header com botão de voltar (chip azul claro), stats em 4 cards (total/enviados/pendentes/falharam) com ícones coloridos, bloco de info com badge de status, filtros, tabela de notificações com avatar em gradiente e badges de status coloridos, paginação, e o modal "Mensagem Enviada" abrindo ao clicar em "Ver" (testar abrir/fechar pelo X, pelo backdrop e pela tecla Esc — comportamento não deve ter mudado). Escuro: repetir e confirmar que o modal, os cards de stats e a tabela trocam de fundo/texto corretamente; os ícones/badges (cores literais de tag) continuam legíveis sobre o novo fundo escuro.

- [ ] **Step 4: Commit**

```bash
git add app/views/campaigns/show.html.erb app/assets/stylesheets/pages/campaigns.scss
git commit -m "style: migrate campaigns#show to token-based design system"
```

---

### Task 38: `campaigns/_form.html.erb` → `pages/campaigns.scss` (seção form)

Reusada por `campaigns/new.html.erb` e `campaigns/edit.html.erb` (cada uma só tem `<% title ... %>` + `render 'form', campaign: @campaign, read_only: false` — nenhuma mudança necessária nelas).

**Files:**
- Modify: `app/views/campaigns/_form.html.erb:1-410` (edições de classe + remoção do `<style>`)
- Modify: `app/assets/stylesheets/pages/campaigns.scss` (acrescenta seção `campaigns/_form`)

**Interfaces:**
- Consumes: tokens, `.crm-btn`/`.crm-btn--primary`/`.crm-btn--secondary`, `.crm-input`, `.crm-label`.
- Produces: `.cpform-btn--outline` (modificador local encadeado com `crm-btn`, variante não coberta pelo componente).

- [ ] **Step 1: Trocar labels/inputs/textarea por `.crm-label`/`.crm-input`**

Todas as ocorrências de `class: 'cpform-field__label'` em `form.label` (linhas 64, 68, 80, 98, 107, 111, 132, 137, 144, 151, 168, 172, 196) trocam para `class: 'crm-label'`. Todas as ocorrências de `class: 'cpform-field__input'` (com ou sem sufixo `cpform-field__input--select`/`--half`) em `form.text_field`/`form.select`/`form.number_field`/`form.date_field` (linhas 65, 69-75, 101, 108, 112, 133, 138, 145, 169, 173) trocam o `cpform-field__input` por `crm-input`, preservando o sufixo quando houver (ex.: `crm-input cpform-field__input--select`, `crm-input cpform-field__input--half`). `form.text_area :message` (linha 197, classe `cpform-field__textarea`) também vira `crm-input` (mantendo `rows: 7`).

Exemplo representativo (linha 64-65):
```erb
# antes
<%= form.label :name, 'Nome da Campanha', class: 'cpform-field__label' %>
<%= form.text_field :name, class: 'cpform-field__input', required: true, placeholder: 'Ex: Cashback de Pascoa', disabled: read_only %>
# depois
<%= form.label :name, 'Nome da Campanha', class: 'crm-label' %>
<%= form.text_field :name, class: 'crm-input', required: true, placeholder: 'Ex: Cashback de Pascoa', disabled: read_only %>
```

Exemplo com select (linha 68-76):
```erb
# antes
<%= form.label :kind, 'Tipo de Campanha', class: 'cpform-field__label' %>
<%= form.select :kind,
    [['Cashback', 'cashback'], ['Expiracao de Cashback', 'cashback_expiration'], ['Notificacao de Marketing', 'marketing_notification']],
    {},
    class: 'cpform-field__input cpform-field__input--select',
    disabled: read_only,
    id: 'campaign_kind',
    onchange: 'updateCampaignLabels()' %>
# depois
<%= form.label :kind, 'Tipo de Campanha', class: 'crm-label' %>
<%= form.select :kind,
    [['Cashback', 'cashback'], ['Expiracao de Cashback', 'cashback_expiration'], ['Notificacao de Marketing', 'marketing_notification']],
    {},
    class: 'crm-input cpform-field__input--select',
    disabled: read_only,
    id: 'campaign_kind',
    onchange: 'updateCampaignLabels()' %>
```

O `id: 'campaign_kind'` e o `onchange: 'updateCampaignLabels()'` **não mudam** — o `<script>` no fim do arquivo depende deles.

- [ ] **Step 2: Trocar botões do rodapé por `.crm-btn`**

```erb
# linha 292, antes
<%= link_to campaigns_path, class: 'cpform-btn cpform-btn--secondary' do %>
# depois
<%= link_to campaigns_path, class: 'crm-btn crm-btn--secondary' do %>
```
```erb
# linha 299, antes
<%= link_to campaign_path(campaign), class: 'cpform-btn cpform-btn--outline' do %>
# depois
<%= link_to campaign_path(campaign), class: 'crm-btn cpform-btn--outline' do %>
```
```erb
# linha 307, antes
<%= form.button class: 'cpform-btn cpform-btn--primary',
    data: { disable_with: campaign.new_record? ? 'Criando...' : 'Salvando...' } do %>
# depois
<%= form.button class: 'crm-btn crm-btn--primary',
    data: { disable_with: campaign.new_record? ? 'Criando...' : 'Salvando...' } do %>
```

- [ ] **Step 3: Remover o `<style>` inline (linhas 322-410) e criar a seção `campaigns/_form` em `pages/campaigns.scss`**

Deletar o bloco `<style>...</style>` do partial. Acrescentar ao final de `pages/campaigns.scss` (após a seção `campaigns/show` da Task 37):

```scss
// ===== campaigns/_form =====
.cpform-wrapper { padding: 1.5rem 2rem; display: flex; justify-content: center; }

.cpform-card { background: var(--bg); border: 1px solid var(--outline); border-radius: var(--radius); box-shadow: 0 2px 12px rgba(30,40,100,0.07); width: 100%; overflow: hidden; }

.cpform-card__header { display: flex; align-items: center; gap: 1rem; padding: 1.5rem 1.75rem; border-bottom: 1px solid var(--outline); background: var(--primary); }
.cpform-card__header-icon { width: 44px; height: 44px; border-radius: var(--radius); background: linear-gradient(135deg, #f59e0b, #fbbf24); color: #fff; display: flex; align-items: center; justify-content: center; flex-shrink: 0; }
.cpform-card__title { font-size: 1.05rem; font-weight: 700; color: #ffffff; margin: 0; }
.cpform-card__subtitle { font-size: 0.8rem; color: var(--primary-tint); margin: 0.15rem 0 0; }

.cpform-alert { display: flex; align-items: flex-start; gap: 0.75rem; padding: 1rem 1.5rem; font-size: 0.85rem; }
.cpform-alert--danger { background: #fce8e6; border-bottom: 1px solid #f6b3ae; color: #c5221f; }
.cpform-alert__icon { flex-shrink: 0; color: #c5221f; margin-top: 1px; }
.cpform-alert strong { display: block; margin-bottom: 0.25rem; }
.cpform-alert p { margin: 0; }

.cpform-errors { display: flex; align-items: flex-start; gap: 0.75rem; padding: 1rem 1.5rem; background: #fce8e6; border-bottom: 1px solid #f6b3ae; color: #c5221f; font-size: 0.85rem; }
.cpform-errors__icon { flex-shrink: 0; color: #c5221f; }
.cpform-errors ul { margin: 0.5rem 0 0 1rem; padding: 0; }
.cpform-errors li { margin: 0.25rem 0; }

.cpform-card__body { padding: 1.75rem; display: flex; flex-direction: column; gap: 1.5rem; }

.cpform-section { background: var(--primary-tint); border: 1px solid var(--outline); border-radius: var(--radius); padding: 1.25rem; display: flex; flex-direction: column; gap: 1rem; }
.cpform-section--highlight { background: #eff6ff; border-color: #bfdbfe; }
.cpform-section--message { background: #f0fdf4; border-color: #bbf7d0; }
.cpform-section--filters { background: #faf5ff; border-color: #e9d5ff; }
.cpform-section__header--filters { color: #7c3aed; }
.cpform-section__description { font-size: 0.85rem; color: var(--fg-alt); margin: -0.5rem 0 0.5rem 0; }
.cpform-section__header { display: flex; align-items: center; gap: 0.5rem; font-weight: 600; font-size: 0.9rem; color: var(--fg); margin-bottom: 0.5rem; }
.cpform-section__header--highlight { color: #1e40af; }
.cpform-section__header--message { color: #166534; }

.cpform-row { display: grid; grid-template-columns: 1fr 1fr; gap: 1rem; }
@media (max-width: 600px) { .cpform-row { grid-template-columns: 1fr; } }

.cpform-field { display: flex; flex-direction: column; gap: 0.35rem; }
.cpform-field__input--select { appearance: none; background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='12' fill='none' viewBox='0 0 24 24' stroke='%236a6f71' stroke-width='2'%3E%3Cpath stroke-linecap='round' stroke-linejoin='round' d='M19 9l-7 7-7-7'/%3E%3C/svg%3E"); background-repeat: no-repeat; background-position: right 0.85rem center; padding-right: 2.5rem; cursor: pointer; }
.cpform-field__input--half { max-width: 200px; }
.cpform-field__hint { font-size: 0.75rem; color: var(--fg-alt); }

.cpform-toggle { display: flex; align-items: center; gap: 0.75rem; }
.cpform-toggle__input { width: 18px; height: 18px; accent-color: var(--primary); cursor: pointer; }
.cpform-toggle__label { font-size: 0.875rem; color: var(--fg); }

.cpform-variables { display: flex; align-items: center; gap: 0.75rem; flex-wrap: wrap; padding-top: 0.5rem; border-top: 1px dashed #bbf7d0; }
.cpform-variables__title { font-size: 0.78rem; font-weight: 600; color: #166534; }
.cpform-variables__list { display: flex; gap: 0.5rem; flex-wrap: wrap; }
.cpform-variables__item { background: var(--bg); border: 1px solid #bbf7d0; padding: 0.2rem 0.5rem; border-radius: 4px; font-size: 0.75rem; color: #166534; cursor: default; }
.cpform-variables__item:hover { background: #dcfce7; }

.cpform-hint-box { display: flex; align-items: flex-start; gap: 0.6rem; padding: 0.85rem 1rem; border-radius: var(--radius); font-size: 0.82rem; line-height: 1.5; }
.cpform-hint-box code { background: rgba(0,0,0,0.08); padding: 0.1rem 0.3rem; border-radius: 3px; font-size: 0.78rem; }
.cpform-hint-box--blue { background: var(--primary-tint); color: var(--primary); border: 1px solid #bfdbfe; }
.cpform-hint-box--orange { background: #fff7ed; color: #9a3412; border: 1px solid #fed7aa; }
.cpform-hint-box--purple { background: #faf5ff; color: #7c3aed; border: 1px solid #e9d5ff; }

.cpform-variables--marketing { border-top-color: #e9d5ff; }
.cpform-variables--marketing .cpform-variables__title { color: #7c3aed; }
.cpform-variables--marketing .cpform-variables__item { border-color: #e9d5ff; color: #7c3aed; }
.cpform-variables--marketing .cpform-variables__item:hover { background: #faf5ff; }

.cpform-status-grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 1rem; }
@media (max-width: 500px) { .cpform-status-grid { grid-template-columns: 1fr; } }
.cpform-status-item { display: flex; flex-direction: column; gap: 0.25rem; }
.cpform-status-item__label { font-size: 0.75rem; color: var(--fg-alt); text-transform: uppercase; letter-spacing: 0.04em; }
.cpform-status-item__value { font-size: 0.9rem; font-weight: 500; color: var(--fg); }
.cpform-status-item__value--running { color: #1d7a3e; }
.cpform-status-item__value--pending { color: var(--primary); }
.cpform-status-item__value--finished { color: var(--fg-alt); }
.cpform-status-item__value--inactive { color: #c5221f; }
.cpform-status-item__value--success { color: #1d7a3e; }
.cpform-status-item__value--danger { color: #c5221f; }

.cpform-card__footer { display: flex; align-items: center; justify-content: flex-end; gap: 0.75rem; padding: 1.25rem 1.75rem; border-top: 1px solid var(--outline); background: var(--primary-tint); }

.cpform-btn--outline { background: var(--bg); color: var(--primary); border: 1px solid var(--primary); }
```

Notas: (1) `.cpform-field__label`, `.cpform-field__input`, `.cpform-field__textarea` e as regras de `:focus`/`:disabled` deixam de existir — cobertas por `.crm-label`/`.crm-input`. (2) Os `.cpform-status-item__label`/`__value` no original tinham `color: #ffffff` fixo (bug visual pré-existente, provavelmente herdado ao copiar do header) — corrigido aqui para `var(--fg-alt)`/`var(--fg)` como o resto da seção de status, já que essa seção não tem fundo escuro; sinalizar essa correção no code review. (3) `.cpform-hint-box--orange`/`--purple` e as cores de `.cpform-section--message`/`--filters`/`--highlight` permanecem literais — são realces semânticos (cashback/expiração/marketing) sem token equivalente no design system atual.

- [ ] **Step 4: Verificar visualmente**

Abrir `/crm/campaigns/new` e `/crm/campaigns/:id/edit`. Claro: card com header azul (`var(--primary)`) e ícone laranja, campos com `crm-input`/`crm-label`, seção "Configuração de Envio" (azul clara) ou "Filtros de Clientes" (roxa) alternando conforme o `<select>` Tipo de Campanha (testar o `onchange` — `updateCampaignLabels()` deve continuar trocando labels/hints/seções sem erros no console), seção "Mensagem" (verde) com variáveis disponíveis, grid de status (só em edição) com cores por status, rodapé com botões Voltar/Ver notificações/Salvar. Escuro: repetir e confirmar que o card, os inputs e o rodapé trocam de fundo/texto; as seções coloridas (azul/verde/roxa/laranja) mantêm suas cores literais mas checar contraste de texto sobre fundo escuro geral da página.

- [ ] **Step 5: Rodar a suíte de testes de controller/model afetada**

Run: `bin/rails test test/controllers -n "/[Cc]ampaign/"` (ou `bin/rails test` completo se o filtro não pegar nada, para garantir que nenhuma mudança de classe quebrou algum teste de view/integration que assert por CSS).
Expected: sem falhas novas relacionadas a `campaigns`.

- [ ] **Step 6: Commit**

```bash
git add app/views/campaigns/_form.html.erb app/assets/stylesheets/pages/campaigns.scss
git commit -m "style: migrate campaigns form partial to token-based design system"
```

---

### Task 39: `affiliates/index.html.erb` → `pages/affiliates.scss` (criação)

**Files:**
- Modify: `app/views/affiliates/index.html.erb:1-243`
- Create: `app/assets/stylesheets/pages/affiliates.scss`
- Modify: `app/assets/stylesheets/admin.scss` — **só necessário se a Task 36 não tiver sido aplicada ainda**; caso contrário o require de `pages/affiliates` já foi adicionado no Step 6 da Task 36 e este step vira um no-op (confirme antes de editar).

**Interfaces:**
- Consumes: tokens, `.crm-btn`/`.crm-btn--primary`/`.crm-btn--secondary`, `.crm-input`, `.crm-label`, `.crm-table`, `.crm-tag`/`.crm-tag--success`/`--danger`/`--warning`/`--neutral`, `.crm-tag--info` (classe já disponível globalmente desde a Task 8 — não precisa ser redefinida aqui, `pages/affiliates.scss` só usa a classe compartilhada).
- Produces: `.affiliates-btn--success`/`--icon`/`--danger`/`--view` (modificadores locais de `crm-btn`).

- [ ] **Step 1: Trocar botões por `.crm-btn`**

```erb
# linha 20, antes
<%= button_tag class: 'affiliates-btn affiliates-btn--primary', name: '' do %>
# depois
<%= button_tag class: 'crm-btn crm-btn--primary', name: '' do %>
```
```erb
# linha 26, antes
<%= link_to affiliates_path, class: 'affiliates-btn affiliates-btn--secondary' do %>
# depois
<%= link_to affiliates_path, class: 'crm-btn crm-btn--secondary' do %>
```
```erb
# linha 32, antes
<%= link_to new_affiliate_path, class: 'affiliates-btn affiliates-btn--success' do %>
# depois
<%= link_to new_affiliate_path, class: 'crm-btn affiliates-btn--success' do %>
```
```erb
# linhas 119-121, antes
<%= link_to events_path(utm_code: affiliate.utm_code),
      class: 'affiliates-btn affiliates-btn--icon affiliates-btn--view',
      title: "Ver eventos de #{affiliate.name}" do %>
# depois
<%= link_to events_path(utm_code: affiliate.utm_code),
      class: 'crm-btn affiliates-btn--icon affiliates-btn--view',
      title: "Ver eventos de #{affiliate.name}" do %>
```
```erb
# linha 128, antes
<%= link_to edit_affiliate_path(affiliate), class: 'affiliates-btn affiliates-btn--icon' do %>
# depois
<%= link_to edit_affiliate_path(affiliate), class: 'crm-btn affiliates-btn--icon' do %>
```
```erb
# linha 133, antes
<%= link_to affiliate_path(affiliate), method: :delete, data: { confirm: 'Tem certeza que deseja excluir este afiliado?' }, class: 'affiliates-btn affiliates-btn--icon affiliates-btn--danger' do %>
# depois
<%= link_to affiliate_path(affiliate), method: :delete, data: { confirm: 'Tem certeza que deseja excluir este afiliado?' }, class: 'crm-btn affiliates-btn--icon affiliates-btn--danger' do %>
```
```erb
# linha 150, antes
<%= link_to new_affiliate_path, class: 'affiliates-btn affiliates-btn--primary' do %>
# depois
<%= link_to new_affiliate_path, class: 'crm-btn crm-btn--primary' do %>
```

- [ ] **Step 2: Trocar labels/inputs do filtro por `.crm-label`/`.crm-input`**

```erb
# linhas 10,14, antes
<label>Buscar</label>
<label>Status</label>
# depois
<label class="crm-label">Buscar</label>
<label class="crm-label">Status</label>
```
```erb
# linha 11, antes
<%= text_field_tag :search, params[:search], class: 'affiliates-filters__input', placeholder: 'Nome, e-mail ou código UTM...' %>
# depois
<%= text_field_tag :search, params[:search], class: 'crm-input', placeholder: 'Nome, e-mail ou código UTM...' %>
```
```erb
# linhas 15-17, antes
<%= select_tag :status,
    options_for_select([['Todos', ''], ['Ativos', 'active'], ['Inativos', 'inactive']], params[:status]),
    class: 'affiliates-filters__input affiliates-filters__input--select' %>
# depois
<%= select_tag :status,
    options_for_select([['Todos', ''], ['Ativos', 'active'], ['Inativos', 'inactive']], params[:status]),
    class: 'crm-input affiliates-filters__input--select' %>
```

- [ ] **Step 3: Trocar a tabela principal por `.crm-table`**

```erb
# linha 61, antes
<table class="affiliates-table">
# depois
<table class="crm-table">
```

- [ ] **Step 4: Trocar badges por `.crm-tag`**

```erb
# linhas 89-98, antes
<% if affiliate.utm_code.present? %>
  <span class="affiliates-table__badge affiliates-table__badge--utm">
    ...
    <%= affiliate.utm_code %>
  </span>
<% else %>
  <span class="affiliates-table__no-utm">Não definido</span>
<% end %>
# depois
<% if affiliate.utm_code.present? %>
  <span class="crm-tag crm-tag--info">
    ...
    <%= affiliate.utm_code %>
  </span>
<% else %>
  <span class="affiliates-table__no-utm">Não definido</span>
<% end %>
```
```erb
# linhas 101-111, antes
<% if affiliate.discount_code.present? %>
  <span class="affiliates-table__badge affiliates-table__badge--coupon">
    ...
    <%= affiliate.discount_code %>
  </span>
<% else %>
  <span class="affiliates-table__no-utm">-</span>
<% end %>
# depois
<% if affiliate.discount_code.present? %>
  <span class="crm-tag crm-tag--warning">
    ...
    <%= affiliate.discount_code %>
  </span>
<% else %>
  <span class="affiliates-table__no-utm">-</span>
<% end %>
```

(o SVG interno de cada badge não muda, só a classe do `<span>` externo.)

- [ ] **Step 5: Remover o `<style>` inline (linhas 172-243) e criar `app/assets/stylesheets/pages/affiliates.scss`**

Deletar o bloco `<style>...</style>` do view. Criar o arquivo:

```scss
// ===== affiliates/index =====
.affiliates-wrapper { padding: 1.5rem 2rem; }

.affiliates-client-info { display: flex; align-items: center; gap: 0.75rem; padding: 0.85rem 1.25rem; background: var(--primary-tint); border: 1px solid var(--outline); border-radius: var(--radius); margin-bottom: 1.5rem; }
.affiliates-client-info__label { font-size: 0.8rem; color: var(--fg-alt); }
.affiliates-client-info__name { font-weight: 600; color: var(--fg); }

.affiliates-filters {
  background: var(--bg);
  border: 1px solid var(--outline);
  border-radius: var(--radius);
  padding: 1.1rem 1.5rem;
  margin-bottom: 1.5rem;
  box-shadow: 0 1px 4px rgba(0,0,0,0.05);
}
.affiliates-filters__row { display: flex; flex-wrap: wrap; gap: 0.85rem; align-items: flex-end; }
.affiliates-filters__field { display: flex; flex-direction: column; gap: 0.3rem; flex: 1; min-width: 180px; }
.affiliates-filters__field--small { flex: 0 0 140px; min-width: 140px; }
.affiliates-filters__input--select {
  appearance: none;
  background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='12' fill='none' viewBox='0 0 24 24' stroke='%236a6f71' stroke-width='2'%3E%3Cpath stroke-linecap='round' stroke-linejoin='round' d='M19 9l-7 7-7-7'/%3E%3C/svg%3E");
  background-repeat: no-repeat;
  background-position: right 0.75rem center;
  padding-right: 2rem;
  cursor: pointer;
}
.affiliates-filters__actions { display: flex; gap: 0.5rem; align-items: flex-end; }

// Modificadores locais de crm-btn
.affiliates-btn--success { background: #1d7a3e; color: #fff; }
.affiliates-btn--icon { padding: 0.4rem 0.6rem; font-size: 0.82rem; }
.affiliates-btn--danger { color: #c5221f; border-color: #f6b3ae; background: #fce8e6; }
.affiliates-btn--danger:hover { background: #f9d3ce; }
.affiliates-btn--view { color: var(--primary); border-color: var(--primary); background: var(--primary-tint); }
.affiliates-btn--view:hover { filter: brightness(.95); }

// Extensão local de crm-tag (variante "info" azul — mesma paleta usada em pages/campaigns.scss)

.affiliates-table-wrap { background: var(--bg); border: 1px solid var(--outline); border-radius: var(--radius); box-shadow: 0 1px 4px rgba(0,0,0,0.05); overflow: hidden; }
.affiliates-table-header { display: flex; align-items: center; justify-content: space-between; padding: 1rem 1.5rem; border-bottom: 1px solid var(--outline); }
.affiliates-table-header__title { display: flex; align-items: center; gap: 0.5rem; font-weight: 600; color: var(--fg); font-size: 0.95rem; }
.affiliates-table-header__count { font-size: 0.8rem; color: var(--fg-alt); background: var(--primary-tint); padding: 0.25rem 0.65rem; border-radius: 999px; }

.affiliates-table-wrap .crm-table tfoot td { padding: 0.75rem 1.25rem; font-size: 0.8rem; color: var(--fg-alt); }

.affiliates-table__id { font-size: 0.75rem; color: var(--fg-alt); }
.affiliates-table__email { color: var(--primary); }
.affiliates-table__phone { color: var(--fg); }
.affiliates-table__date { color: var(--fg-alt); font-size: 0.82rem; }
.affiliates-table__no-utm { color: var(--fg-alt); font-size: 0.82rem; font-style: italic; }

.affiliates-table__actions { display: flex; gap: 0.35rem; justify-content: center; }

.affiliates-table__empty { text-align: center; padding: 3rem !important; }
.affiliates-table__empty-content { display: flex; flex-direction: column; align-items: center; gap: 1rem; color: var(--fg-alt); }
.affiliates-table__empty-content svg { opacity: 0.5; }
.affiliates-table__empty-content p { margin: 0; }

.affiliates-pagination { display: flex; list-style: none; gap: 0.4rem; padding: 1rem 1.5rem; margin: 0; justify-content: center; }
.affiliates-pagination li a, .affiliates-pagination li span { display: inline-flex; align-items: center; justify-content: center; min-width: 32px; height: 32px; padding: 0 0.5rem; border-radius: var(--radius); font-size: 0.82rem; font-weight: 500; border: 1px solid var(--outline); color: var(--fg); text-decoration: none; transition: all 0.15s; }
.affiliates-pagination li.current span { background: var(--primary); color: #fff; border-color: var(--primary); }
.affiliates-pagination li a:hover { background: var(--primary-tint); border-color: var(--primary); }
.text-center { text-align: center; }
```

- [ ] **Step 6: Confirmar/ajustar o require em `app/assets/stylesheets/admin.scss`**

Se a Task 36 já rodou, a linha `*= require pages/affiliates` já existe (adicionada em conjunto naquele Step 6) — não faça nada. Se esta task está rodando isoladamente/antes da E-1, adicione:

```scss
# antes
 *= require layouts/customers
 *= require_self
```
```scss
# depois
 *= require layouts/customers
 *= require pages/campaigns
 *= require pages/affiliates
 *= require_self
```

- [ ] **Step 7: Verificar visualmente**

Abrir `/crm/affiliates` (index). Claro: filtros, tabela com colunas Afiliado/E-mail/Telefone/Código UTM/Cupom/Cadastro/Ações, badge azul do código UTM, badge âmbar do cupom, botões de ação (ver eventos, editar, excluir) como ícones. Escuro: alternar tema e confirmar contraste de tabela/filtros/paginação.

- [ ] **Step 8: Commit**

```bash
git add app/views/affiliates/index.html.erb app/assets/stylesheets/pages/affiliates.scss app/assets/stylesheets/admin.scss
git commit -m "style: migrate affiliates#index to token-based design system"
```

---

### Task 40: `affiliates/show.html.erb` → `pages/affiliates.scss` (seção show)

**Files:**
- Modify: `app/views/affiliates/show.html.erb:343-524` (remove o `<style>`)
- Modify: `app/assets/stylesheets/pages/affiliates.scss` (acrescenta seção `affiliates/show`, arquivo já criado pela Task 39)

**Interfaces:**
- Consumes: tokens (`var(--*)`, incluindo `var(--chrome-bg)`/`var(--chrome-fg)` para o painel escuro do funil). Segue a regra do bloco grande: move o `<style>` e aplica a tabela de substituição, sem trocar classes por componentes.
- Produces: seção `affiliates/show` em `pages/affiliates.scss`.

- [ ] **Step 1: Remover o `<style>` inline (linhas 343-524) de `affiliates/show.html.erb`**

Não mexer em nenhum outro trecho do arquivo — os `style="..."` inline nos elementos (barras de funil, ícones de dispositivo, células do heatmap, linhas 128-267 aproximadamente) são gerados dinamicamente por Ruby (`step[:color]`, `bg_color`, `pct`, etc.) e ficam fora do escopo desta migração — eles não fazem parte do bloco `<style>` e continuam funcionando como estão, ainda que fiquem "fixos" (não reagem ao tema escuro). Isso é uma limitação conhecida a ser resolvida em uma iteração futura, não bloqueia esta task.

- [ ] **Step 2: Mover o conteúdo para `pages/affiliates.scss`, seção `affiliates/show`**

Ler o bloco original em `app/views/affiliates/show.html.erb:343-524` e colar seu conteúdo integral ao final de `pages/affiliates.scss` (após a seção `affiliates/index` da Task 39), sob `// ===== affiliates/show =====`, aplicando a tabela de substituição do topo deste documento. Pontos específicos desta folha:

- `.aff-page`, `.aff-header`, `.aff-info-card`, `.aff-empty`, `.aff-kpi`, `.aff-card`, `.aff-table-card` (fundos `#fff`, bordas `#e2e8f0`) → `var(--bg)` / `var(--outline)`, raios `12px`/`14px`/`10px` → `var(--radius)`.
- Textos `#0f172a`/`#334155` → `var(--fg)`; `#64748b`/`#94a3b8`/`#475569` → `var(--fg-alt)`.
- `.aff-filter-btn--active` (fundo `#fff`) → `var(--bg)`; `.aff-filters` (fundo `#f8fafc`) → `var(--primary-tint)`.
- `.aff-btn--primary` (`background: #0f172a`) e seu hover `#1e293b` — **exceção**: mantenha literal (é um botão propositalmente monocromático "quase preto", não o azul de marca; não é o mesmo padrão de `.crm-btn--primary`). `.aff-btn--secondary` (`#f1f5f9`/`#475569`/borda `#e2e8f0`) → `var(--primary-tint)` / `var(--fg)` / `var(--outline)`.
- `.aff-info-card__avatar` (`background: #dbeafe`, `color: #3b82f6`) → `var(--primary-tint)` / `var(--primary)`.
- `.aff-utm-code` (`background: #dbeafe`, `color: #1d4ed8`) → `var(--primary-tint)` / `var(--primary)`.
- `.aff-kpi::before` cores por variante (`--blue`/`--green`/`--amber`/`--rose`/`--purple`) são uma paleta de dados intencionalmente multicor — **mantenha literal**, sem token.
- `.aff-funnel-section` — **exceção com token dedicado**: troque `background: linear-gradient(135deg, #0f172a 0%, #1e293b 100%);` por `background: var(--chrome-bg);` (era um painel propositalmente escuro em ambos os temas; `--chrome-bg` já modela exatamente esse "sempre escuro que muda de tom entre claro/escuro"). Dentro dela, `color: #fff` nos textos → `var(--chrome-fg)`; `color: #94a3b8` (legendas) mantenha literal (não há "chrome-fg-alt" no design system) ou aproxime para `rgba(243,244,246,.6)` — escolha manter `#94a3b8` literal para simplicidade.
- `.aff-devices`/`.aff-top-list` (bordas `#f1f5f9`, textos `#334155`/`#94a3b8`) seguem a tabela genérica.
- `.aff-table thead th` (fundo `#f8fafc`) → `var(--primary-tint)`; linha convertida `.aff-table__row--converted` (`#f0fdf4`/hover `#dcfce7`) — **mantenha literal**, é um verde semântico de "sessão convertida", sem token dedicado.
- `.aff-badge--*` seguem a paleta de tags da tabela genérica (`--page`/`--product`/`--cart`/`--checkout` são uma paleta de dados categórica intencional — mantenha literal; `--success`/`--warning` seguem sucesso/aviso; `--count` continua `background:#0f172a` propositalmente escuro, mantenha literal).
- Todos os `border-radius: 6px/8px/10px/12px/16px` → `var(--radius)`; `border-radius: 999px`/pill continuam como estão (não há pill nesta folha além dos badges, que já usam `border-radius: 6px`, mantenha esse valor literal pois não é um "pill" — vira `var(--radius)`).

- [ ] **Step 3: Verificar visualmente**

Abrir `/crm/affiliates/:id` (analytics de um afiliado com eventos). Claro: header com breadcrumb, filtros de período (7/15/30/90 dias), card de info do afiliado, KPIs, funil de conversão (painel escuro), grid de produtos mais visitados + dispositivos/origens, heatmap de horários, tabela de sessões recentes com badges. Também testar o estado vazio (afiliado sem `utm_code` e afiliado sem eventos no período). Escuro: alternar tema — confirmar que o painel do funil continua escuro e legível (agora via `var(--chrome-bg)`/`var(--chrome-fg)`), e que os cards/tabela/header claros trocam de fundo/texto; heatmap e barras de funil (estilo inline dinâmico) continuam com as cores originais, não reagem ao tema (esperado, ver Step 1).

- [ ] **Step 4: Commit**

```bash
git add app/views/affiliates/show.html.erb app/assets/stylesheets/pages/affiliates.scss
git commit -m "style: migrate affiliates#show to token-based design system"
```

---

### Task 41: `affiliates/_form.html.erb` + `affiliates/_form_styles.html.erb` → `pages/affiliates.scss` (seção form)

Confirmado ao ler `affiliates/new.html.erb` e `affiliates/edit.html.erb`: ambos só montam o header da página (`affiliates-page-header`, com botão Voltar e, no caso de edit, título + badge `affiliates-table__badge--utm` + nome), envolvem `render 'form', form_url:, form_method:` dentro de `.affiliates-form-wrap`, e no fim chamam `<%= render 'form_styles' %>` — ou seja, `_form_styles.html.erb` é de fato o parceiro de estilos desses dois views (não da partial `_form` isolada; `_form.html.erb` tem seu próprio `<style>` menor, só do card-header verde). As duas folhas de estilo são migradas juntas nesta task porque cobrem o mesmo conjunto de páginas (new/edit de afiliado) e têm seletores complementares sem sobreposição real (só `.affiliates-btn`/`.affiliates-table__badge--utm`, que a Task 39 já deixou como componentes/tokens — aqui só confirmamos que continuam funcionando).

**Files:**
- Modify: `app/views/affiliates/_form.html.erb:1-141`
- Modify: `app/views/affiliates/new.html.erb:1-22` (classe do badge/título já tratada pela Task 39 nada a mudar aqui além de nada — ver Step 4)
- Modify: `app/views/affiliates/edit.html.erb:1-32`
- Modify: `app/assets/stylesheets/pages/affiliates.scss` (acrescenta seção `affiliates/_form`)

**Interfaces:**
- Consumes: tokens, `.crm-btn`/`.crm-btn--primary`/`.crm-btn--secondary`, `.crm-input`, `.crm-label`, `.crm-tag--info` (já produzida na Task 39, reaproveitada em `new.html.erb`/`edit.html.erb`).
- Produces: `.affiliates-btn--success` (já produzido na Task 39, reaproveitado aqui).

- [ ] **Step 1: Trocar labels/inputs por `.crm-label`/`.crm-input` em `_form.html.erb`**

O form usa `<label for="...">Texto</label>` solto (sem classe) seguido do helper do Rails — adicionar `class="crm-label"` em cada `<label>` e trocar `class: 'affiliates-form__input'` por `class: 'crm-input'` em cada helper:

```erb
# linhas 31-32, antes
<label for="user_name">Nome *</label>
<%= f.text_field :name, class: 'affiliates-form__input', placeholder: 'Nome completo do afiliado', required: true %>
# depois
<label for="user_name" class="crm-label">Nome *</label>
<%= f.text_field :name, class: 'crm-input', placeholder: 'Nome completo do afiliado', required: true %>
```

O mesmo padrão (adicionar `class="crm-label"` ao `<label>`, trocar `affiliates-form__input` → `crm-input` no helper) se repete de forma idêntica para:
- linhas 38-39 (`user_email` / `f.email_field :email`)
- linhas 42-43 (`user_phone` / `f.text_field :phone`)
- linhas 53-54 (`user_utm_code` / `f.text_field :utm_code`)
- linhas 64-65 (`user_discount_code` / `f.text_field :discount_code`)
- linhas 86-87 (`user_password` / `f.password_field :password`)
- linhas 90-91 (`user_password_confirmation` / `f.password_field :password_confirmation`)

- [ ] **Step 2: Trocar botões do rodapé por `.crm-btn` em `_form.html.erb`**

```erb
# linha 97, antes
<%= link_to affiliates_path, class: 'affiliates-btn affiliates-btn--secondary' do %>
# depois
<%= link_to affiliates_path, class: 'crm-btn crm-btn--secondary' do %>
```
```erb
# linha 100, antes
<%= f.submit (@affiliate.new_record? ? 'Criar Afiliado' : 'Salvar Alterações'), class: "affiliates-btn #{@affiliate.new_record? ? 'affiliates-btn--success' : 'affiliates-btn--primary'}" %>
# depois
<%= f.submit (@affiliate.new_record? ? 'Criar Afiliado' : 'Salvar Alterações'), class: "crm-btn #{@affiliate.new_record? ? 'affiliates-btn--success' : 'crm-btn--primary'}" %>
```

- [ ] **Step 3: Remover o `<style>` de `_form.html.erb` (linhas 104-141) e acrescentar a `pages/affiliates.scss`**

```scss
// ===== affiliates/_form (card-header verde) =====
.affiliates-form__card-header {
  display: flex;
  align-items: center;
  gap: 1rem;
  padding: 1.25rem 1.5rem;
  background: #f0fdf4;
  border-bottom: 1px solid #bbf7d0;
  border-radius: var(--radius) var(--radius) 0 0;
}

.affiliates-form__card-header-icon {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 2.5rem;
  height: 2.5rem;
  border-radius: var(--radius);
  background: #16a34a;
  color: #fff;
  flex-shrink: 0;
}

.affiliates-form__card-title {
  font-size: 1.05rem;
  font-weight: 700;
  color: #14532d;
  margin: 0;
  line-height: 1.3;
}

.affiliates-form__card-subtitle {
  font-size: 0.8rem;
  color: #16a34a;
  margin: 0.15rem 0 0;
  font-weight: 500;
}
```

(Verde mantido literal de propósito — é um realce decorativo do header do formulário, distinto da cor de marca; não há token para isso no design system atual.)

- [ ] **Step 4: Remover o `<style>` de `_form_styles.html.erb` (arquivo inteiro, linhas 1-57) e acrescentar a `pages/affiliates.scss`**

`affiliates/_form_styles.html.erb` fica um partial vazio (sem conteúdo) depois deste step — **não apague o arquivo nem o `render 'form_styles'` em `new.html.erb`/`edit.html.erb`** (fora de escopo remover a chamada; manter o partial como arquivo vazio é seguro e reversível). Conteúdo a acrescentar em `pages/affiliates.scss`:

```scss
// ===== affiliates/new, affiliates/edit (page header) =====
.affiliates-page-header { display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 1rem; margin-bottom: 1.5rem; }
.affiliates-page-header__left { display: flex; align-items: center; gap: 1rem; }
.affiliates-page-header__title { display: flex; align-items: center; gap: 0.6rem; font-size: 1.35rem; font-weight: 700; color: var(--fg); margin: 0; }
.affiliates-page-header__meta { display: flex; align-items: center; gap: 0.65rem; }
.affiliates-page-header__name { font-weight: 500; color: var(--fg); font-size: 0.9rem; }

.affiliates-form-wrap { background: var(--bg); border: 1px solid var(--outline); border-radius: var(--radius); box-shadow: 0 1px 4px rgba(0,0,0,0.05); overflow: hidden; }

.affiliates-form__errors { background: #fce8e6; border: 1px solid #f6b3ae; border-radius: var(--radius); padding: 1rem 1.25rem; margin: 1.5rem; color: #c5221f; }
.affiliates-form__errors strong { display: block; margin-bottom: 0.5rem; }
.affiliates-form__errors ul { margin: 0; padding-left: 1.25rem; }
.affiliates-form__errors li { font-size: 0.875rem; }

.affiliates-form__section { padding: 1.5rem 2rem; border-bottom: 1px solid var(--outline); }
.affiliates-form__section:last-of-type { border-bottom: none; }
.affiliates-form__section-title { font-size: 1rem; font-weight: 600; color: var(--fg); margin: 0 0 0.5rem; }
.affiliates-form__section-desc { font-size: 0.85rem; color: var(--fg-alt); margin: 0 0 1rem; }

.affiliates-form__row { margin-bottom: 1rem; }
.affiliates-form__row:last-child { margin-bottom: 0; }
.affiliates-form__row--two { display: grid; grid-template-columns: 1fr 1fr; gap: 1rem; }
.affiliates-form__row--three { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 1rem; }

.affiliates-form__hint { font-size: 0.75rem; color: var(--fg-alt); margin-top: 0.25rem; }
.affiliates-form__hint code { background: var(--primary-tint); padding: 0.1rem 0.4rem; border-radius: 4px; font-family: monospace; color: var(--primary); }

.affiliates-form__actions { display: flex; justify-content: flex-end; gap: 0.75rem; padding: 1.1rem 2rem; background: var(--primary-tint); border-top: 1px solid var(--outline); }

@media (max-width: 640px) {
  .affiliates-wrapper { padding: 1rem; }
  .affiliates-form__section { padding: 1.25rem 1rem; }
  .affiliates-form__row--two,
  .affiliates-form__row--three { grid-template-columns: 1fr; }
}
```

Notas: as regras antigas `.affiliates-btn*`, `.affiliates-form__field`/`.affiliates-form__input` (cobertas por `crm-input`/`crm-label` desde o Step 1) e `.affiliates-table__badge*` (coberta por `crm-tag`/`crm-tag--info` desde a Task 39) não são recriadas aqui — são as mesmas regras já definidas nas seções anteriores de `pages/affiliates.scss`, sem necessidade de duplicar.

- [ ] **Step 5: Confirmar que `new.html.erb`/`edit.html.erb` continuam usando os badges/botões já migrados**

Nenhuma edição de código é necessária aqui — apenas conferir visualmente (Step 6) que o badge `affiliates-table__badge--utm` em `edit.html.erb:21` (`ID #<%= @affiliate.id %>`) e o botão `affiliates-btn--secondary` em ambos os views (`new.html.erb:7`, `edit.html.erb:7`) ainda renderizam corretamente — essas classes já foram cobertas pelas seções `affiliates/index` (Task 39) e permanecem válidas: `affiliates-table__badge--utm` continua existindo como classe **sem** estilo próprio depois da Task 39? — **atenção**: na Task 39 essa classe foi mantida no HTML da tabela (`affiliate.utm_code`) mas trocada para `crm-tag crm-tag--info` no `<span>` da tabela; aqui em `edit.html.erb:21` o mesmo badge `affiliates-table__badge--utm` é usado isoladamente (fora da tabela) e **precisa da mesma troca**:

```erb
# app/views/affiliates/edit.html.erb, linha 21, antes
<span class="affiliates-table__badge affiliates-table__badge--utm">ID #<%= @affiliate.id %></span>
# depois
<span class="crm-tag crm-tag--info">ID #<%= @affiliate.id %></span>
```

E o botão "Voltar" em ambos os views:
```erb
# app/views/affiliates/new.html.erb linha 7 e affiliates/edit.html.erb linha 7, antes
<%= link_to affiliates_path, class: 'affiliates-btn affiliates-btn--secondary' do %>
# depois
<%= link_to affiliates_path, class: 'crm-btn crm-btn--secondary' do %>
```

- [ ] **Step 6: Verificar visualmente**

Abrir `/crm/affiliates/new` e `/crm/affiliates/:id/edit`. Claro: header da página com botão Voltar (e, em edit, título + badge ID + nome), card do formulário com header verde, seções "Informações Básicas", "Código de Rastreamento" (com hints e `<code>`), "Senha de Acesso"/"Alterar Senha", rodapé com Cancelar/Criar ou Salvar. Testar submit com erro (ex.: deixar e-mail em branco) para ver o bloco de erros vermelho. Escuro: alternar tema e confirmar que o header da página, o card do form e os inputs trocam de fundo/texto; o header verde do card e o bloco de erros mantêm suas cores literais (sem token) mas continuam legíveis.

- [ ] **Step 7: Rodar a suíte de testes de controller afetada**

Run: `bin/rails test test/controllers/clients_controller_test.rb test/controllers -n "/[Aa]ffiliate/"` (ajuste o filtro conforme os testes existentes; se não houver teste de affiliates controller, rodar `bin/rails test` completo).
Expected: sem falhas novas relacionadas a `affiliates`.

- [ ] **Step 8: Commit**

```bash
git add app/views/affiliates/_form.html.erb app/views/affiliates/_form_styles.html.erb app/views/affiliates/new.html.erb app/views/affiliates/edit.html.erb app/assets/stylesheets/pages/affiliates.scss
git commit -m "style: migrate affiliates form partials to token-based design system"
```

---

### Cobertura do require de `admin.scss`

`*= require pages/campaigns` e `*= require pages/affiliates` são adicionados juntos no **Step 6 da Task 36** (antes de `*= require_self`), com um fallback no **Step 6 da Task 39** caso as tasks rodem fora de ordem. Nenhuma outra task deste grupo precisa tocar `admin.scss`.

---

## Área 6 — Admin (Perfis, Usuários, Tentativas)

### Task 42: Migrar `profiles/index.html.erb` para tokens/componentes

**Files:**
- Create: `app/assets/stylesheets/pages/profiles.scss`
- Modify: `app/views/profiles/index.html.erb:1-158`
- Modify: `app/assets/stylesheets/admin.scss` (lista de requires)

**Interfaces:**
- Consumes: `.crm-btn`, `.crm-btn--primary`, `.crm-btn--secondary`, `.crm-input`, `.crm-label`, `.crm-table`, `.crm-tag`, `.crm-tag--neutral`, `.crm-tag--warning` (de `app/assets/stylesheets/components/*.scss`, adicionados por outra task do plano); tokens de `tokens.scss` (`--primary`, `--bg`, `--fg`, `--fg-alt`, `--outline`, `--primary-tint`, `--radius`).
- Produces: `app/assets/stylesheets/pages/profiles.scss` (também consumido pela Task 43, que reaproveita este mesmo arquivo).

**Decisões de mapeamento** (não há variante "success" no `.crm-btn`, só `--primary`/`--secondary`):
- "Filtrar" e "Limpar" → `.crm-btn--secondary` (ações auxiliares do formulário de busca).
- "Novo Perfil" → `.crm-btn--primary` (CTA principal da página).
- Badge "Administrador" (perfil id 1) → `.crm-tag--warning` (mesma cor âmbar do badge antigo).
- Contador "N encontrados" → `.crm-tag--neutral`.
- Ícone do avatar de perfil e paginação não têm componente equivalente pronto — permanecem como CSS de página em `pages/profiles.scss`, usando tokens em vez de cores fixas.

- [ ] **Step 1: Extrair o `<style>` inline para `pages/profiles.scss`**

Remover o bloco abaixo do final de `app/views/profiles/index.html.erb` (linhas 113-158):

```erb
<style>
  .profiles-wrapper { padding: 1.5rem 2rem; }

  .profiles-filters { background: #fff; border: 1px solid #e4e7f0; border-radius: 10px; padding: 1.1rem 1.5rem; margin-bottom: 1.5rem; box-shadow: 0 1px 4px rgba(0,0,0,0.05); }
  .profiles-filters__row { display: flex; flex-wrap: wrap; gap: 0.85rem; align-items: flex-end; }
  .profiles-filters__field { display: flex; flex-direction: column; gap: 0.3rem; flex: 1; min-width: 200px; }
  .profiles-filters__field label { font-size: 0.78rem; font-weight: 600; color: #5a6380; text-transform: uppercase; letter-spacing: 0.04em; }
  .profiles-filters__input { border: 1px solid #e4e7f0; border-radius: 8px; padding: 0.5rem 0.75rem; font-size: 0.875rem; color: #1e2235; background: #f8f9fc; outline: none; transition: border-color 0.15s; }
  .profiles-filters__input:focus { border-color: #3b4adf; background: #fff; }
  .profiles-filters__actions { display: flex; gap: 0.5rem; align-items: flex-end; }

  .profiles-btn { display: inline-flex; align-items: center; gap: 0.4rem; padding: 0.5rem 1rem; border-radius: 8px; font-size: 0.875rem; font-weight: 500; cursor: pointer; border: none; text-decoration: none; transition: opacity 0.15s; }
  .profiles-btn:hover { opacity: 0.88; }
  .profiles-btn--primary { background: #3b4adf; color: #fff; }
  .profiles-btn--secondary { background: #f0f2fb; color: #3b4adf; border: 1px solid #dde1f5; }
  .profiles-btn--success { background: #1d7a3e; color: #fff; }
  .profiles-btn--icon { background: #f0f2fb; color: #3b4adf; border: 1px solid #dde1f5; padding: 0.4rem 0.75rem; font-size: 0.82rem; }

  .profiles-table-wrap { background: #fff; border: 1px solid #e4e7f0; border-radius: 12px; box-shadow: 0 1px 4px rgba(0,0,0,0.05); overflow: hidden; }
  .profiles-table-header { display: flex; align-items: center; justify-content: space-between; padding: 1rem 1.5rem; border-bottom: 1px solid #f0f2f8; }
  .profiles-table-header__title { display: flex; align-items: center; gap: 0.5rem; font-weight: 600; color: #1e2235; font-size: 0.95rem; }
  .profiles-table-header__count { font-size: 0.8rem; color: #9097b5; background: #f4f5fb; padding: 0.25rem 0.65rem; border-radius: 20px; }

  .profiles-table { width: 100%; border-collapse: collapse; }
  .profiles-table thead th { padding: 0.75rem 1.25rem; font-size: 0.75rem; font-weight: 700; color: #9097b5; text-transform: uppercase; letter-spacing: 0.06em; background: #f8f9fc; border-bottom: 1px solid #e4e7f0; }
  .profiles-table tbody td { padding: 0.9rem 1.25rem; border-bottom: 1px solid #f0f2f8; font-size: 0.875rem; color: #3a4060; vertical-align: middle; }
  .profiles-table tbody tr:last-child td { border-bottom: none; }
  .profiles-table tbody tr:hover td { background: #f8f9fc; }
  .profiles-table tfoot td { padding: 0.75rem 1.25rem; font-size: 0.8rem; color: #9097b5; border-top: 1px solid #f0f2f8; }
  .profiles-table__empty { text-align: center; color: #9097b5; padding: 3rem !important; }

  .profiles-table__profile { display: flex; align-items: center; gap: 0.75rem; }
  .profiles-table__icon { width: 36px; height: 36px; border-radius: 10px; background: linear-gradient(135deg, #3b4adf, #6674f5); color: #fff; display: flex; align-items: center; justify-content: center; flex-shrink: 0; }
  .profiles-table__name { font-weight: 600; color: #1e2235; }
  .profiles-table__badge { display: inline-flex; align-items: center; padding: 0.15rem 0.55rem; border-radius: 20px; font-size: 0.7rem; font-weight: 600; margin-top: 0.2rem; }
  .profiles-table__badge--admin { background: #fef3c7; color: #92400e; }
  .profiles-table__id { font-family: monospace; font-size: 0.82rem; background: #f4f5fb; padding: 0.2rem 0.55rem; border-radius: 6px; color: #5a6380; }
  .profiles-table__count { font-weight: 600; color: #3b4adf; }
  .profiles-table__date { color: #6b7280; font-size: 0.82rem; white-space: nowrap; }

  .profiles-pagination { display: flex; list-style: none; gap: 0.4rem; padding: 1rem 1.5rem; margin: 0; justify-content: center; }
  .profiles-pagination li a, .profiles-pagination li span { display: inline-flex; align-items: center; justify-content: center; min-width: 32px; height: 32px; padding: 0 0.5rem; border-radius: 6px; font-size: 0.82rem; font-weight: 500; border: 1px solid #e4e7f0; color: #3a4060; text-decoration: none; transition: all 0.15s; }
  .profiles-pagination li.current span { background: #3b4adf; color: #fff; border-color: #3b4adf; }
  .profiles-pagination li a:hover { background: #f0f2fb; border-color: #b0b8f0; }
  .text-center { text-align: center; }
</style>
```

Criar `app/assets/stylesheets/pages/profiles.scss` com apenas o CSS que não é coberto pelos componentes `.crm-*` (filtros/botões/inputs/tabela genéricos somem, viram classes reaproveitadas no Step 3):

```scss
.profiles-page { padding: 1.5rem 2rem; }

.profiles-page__filters-row { display: flex; flex-wrap: wrap; gap: 0.85rem; align-items: flex-end; }
.profiles-page__filters-field { display: flex; flex-direction: column; gap: 0.3rem; flex: 1; min-width: 200px; }
.profiles-page__filters-actions { display: flex; gap: 0.5rem; align-items: flex-end; }

.profiles-page__table-wrap { padding: 0; overflow: hidden; }
.profiles-page__table-header { display: flex; align-items: center; justify-content: space-between; padding: 1rem 1.5rem; border-bottom: 1px solid var(--outline); }
.profiles-page__table-title { display: flex; align-items: center; gap: 0.5rem; font-weight: 600; color: var(--fg); font-size: 0.95rem; }

.profiles-page__profile { display: flex; align-items: center; gap: 0.75rem; }
.profiles-page__icon { width: 36px; height: 36px; border-radius: var(--radius); background: var(--primary); color: #fff; display: flex; align-items: center; justify-content: center; flex-shrink: 0; }
.profiles-page__name { font-weight: 600; color: var(--fg); }
.profiles-page__id { font-family: monospace; font-size: 0.82rem; background: var(--primary-tint); padding: 0.2rem 0.55rem; border-radius: var(--radius); color: var(--fg-alt); }
.profiles-page__count { font-weight: 600; color: var(--primary); }
.profiles-page__date { color: var(--fg-alt); font-size: 0.82rem; white-space: nowrap; }
.profiles-page__empty { text-align: center; color: var(--fg-alt); padding: 3rem !important; }
.profiles-page__table-wrap tfoot td { color: var(--fg-alt); font-size: 0.8rem; }

.profiles-page__pagination { display: flex; list-style: none; gap: 0.4rem; padding: 1rem 1.5rem; margin: 0; justify-content: center; }
.profiles-page__pagination li a, .profiles-page__pagination li span { display: inline-flex; align-items: center; justify-content: center; min-width: 32px; height: 32px; padding: 0 0.5rem; border-radius: var(--radius); font-size: 0.82rem; font-weight: 500; border: 1px solid var(--outline); color: var(--fg); text-decoration: none; transition: all 0.15s; }
.profiles-page__pagination li.current span { background: var(--primary); color: #fff; border-color: var(--primary); }
.profiles-page__pagination li a:hover { background: var(--primary-tint); border-color: var(--primary); }
```

- [ ] **Step 2: Registrar o require em `admin.scss`**

Em `app/assets/stylesheets/admin.scss`, adicionar (se ainda não existir) `*= require pages/profiles` e `*= require pages/users` à lista de requires, antes de `*= require_self`:

```diff
  *= require layouts/customers
+ *= require pages/profiles
+ *= require pages/users
  *= require_self
```

(`pages/users` ainda não existe neste ponto — será criado na Task 44; o `require` de um arquivo inexistente falha o asset pipeline, então só adicione a linha `require pages/users` quando o arquivo já existir. Se esta task for executada isoladamente antes da F-3, adicione só `require pages/profiles` agora e a F-3 adiciona a outra linha.)

- [ ] **Step 3: Trocar classes do bloco de filtros**

Before (`app/views/profiles/index.html.erb:3-35`):
```erb
<div class="profiles-wrapper">

  <%# Filtros %>
  <%= form_tag(profiles_path, method: 'get') do %>
    <div class="profiles-filters">
      <div class="profiles-filters__row">
        <div class="profiles-filters__field">
          <label>Buscar</label>
          <%= text_field_tag :search, params[:search], class: 'profiles-filters__input', placeholder: 'Nome do perfil...' %>
        </div>
        <div class="profiles-filters__actions">
          <%= button_tag class: 'profiles-btn profiles-btn--primary', name: '' do %>
            ...
            Filtrar
          <% end %>
          <%= link_to profiles_path, class: 'profiles-btn profiles-btn--secondary' do %>
            ...
            Limpar
          <% end %>
          <%= link_to new_profile_path, class: 'profiles-btn profiles-btn--success' do %>
            ...
            Novo Perfil
          <% end %>
        </div>
      </div>
    </div>
  <% end %>
```

After:
```erb
<div class="profiles-page">

  <%# Filtros %>
  <%= form_tag(profiles_path, method: 'get') do %>
    <div class="crm-card profiles-page__filters-row-wrap">
      <div class="profiles-page__filters-row">
        <div class="profiles-page__filters-field">
          <label class="crm-label">Buscar</label>
          <%= text_field_tag :search, params[:search], class: 'crm-input', placeholder: 'Nome do perfil...' %>
        </div>
        <div class="profiles-page__filters-actions">
          <%= button_tag class: 'crm-btn crm-btn--secondary', name: '' do %>
            ...
            Filtrar
          <% end %>
          <%= link_to profiles_path, class: 'crm-btn crm-btn--secondary' do %>
            ...
            Limpar
          <% end %>
          <%= link_to new_profile_path, class: 'crm-btn crm-btn--primary' do %>
            ...
            Novo Perfil
          <% end %>
        </div>
      </div>
    </div>
  <% end %>
```

(o conteúdo dos `<svg>...</svg>` dentro de cada botão não muda — mantenha exatamente como está hoje. `profiles-page__filters-row-wrap` é só o `.crm-card` recebendo `margin-bottom: 1.5rem`; adicione essa regra em `pages/profiles.scss`: `.profiles-page__filters-row-wrap { margin-bottom: 1.5rem; }`.)

- [ ] **Step 4: Trocar classes da tabela, badges e paginação**

Before (`app/views/profiles/index.html.erb:38-111`, trechos relevantes):
```erb
  <div class="profiles-table-wrap">
    <div class="profiles-table-header">
      <span class="profiles-table-header__title">
        ...
        Perfis
      </span>
      <span class="profiles-table-header__count"><%= @profiles.total_entries rescue @profiles.count %> encontrados</span>
    </div>

    <table class="profiles-table">
```
```erb
                <div class="profiles-table__icon">
                  ...
                </div>
                <div>
                  <div class="profiles-table__name"><%= profile.name %></div>
                  <% if profile.id == 1 %>
                    <div class="profiles-table__badge profiles-table__badge--admin">Administrador</div>
                  <% end %>
```
```erb
              <span class="profiles-table__id">#<%= profile.id %></span>
            </td>
            <td class="text-center">
              <span class="profiles-table__count"><%= User.where(profile_id: profile.id).count %></span>
            </td>
            <td class="profiles-table__date">
```
```erb
              <%= link_to edit_profile_path(profile), class: 'profiles-btn profiles-btn--icon' do %>
```
```erb
            <td colspan="5" class="profiles-table__empty">Nenhum perfil encontrado.</td>
```
```erb
    <%= will_paginate @profiles, list_classes: %w[profiles-pagination] %>
  </div>

</div>
```

After:
```erb
  <div class="crm-card profiles-page__table-wrap">
    <div class="profiles-page__table-header">
      <span class="profiles-page__table-title">
        ...
        Perfis
      </span>
      <span class="crm-tag crm-tag--neutral"><%= @profiles.total_entries rescue @profiles.count %> encontrados</span>
    </div>

    <table class="crm-table">
```
```erb
                <div class="profiles-page__icon">
                  ...
                </div>
                <div>
                  <div class="profiles-page__name"><%= profile.name %></div>
                  <% if profile.id == 1 %>
                    <span class="crm-tag crm-tag--warning">Administrador</span>
                  <% end %>
```
```erb
              <span class="profiles-page__id">#<%= profile.id %></span>
            </td>
            <td class="text-center">
              <span class="profiles-page__count"><%= User.where(profile_id: profile.id).count %></span>
            </td>
            <td class="profiles-page__date">
```
```erb
              <%= link_to edit_profile_path(profile), class: 'crm-btn crm-btn--secondary' do %>
```
```erb
            <td colspan="5" class="profiles-page__empty">Nenhum perfil encontrado.</td>
```
```erb
    <%= will_paginate @profiles, list_classes: %w[profiles-page__pagination] %>
  </div>

</div>
```

Também trocar `<div class="profiles-table__profile">` → `<div class="profiles-page__profile">` (linha 64) e remover a linha `<th class="text-center">` — não, essas ficam iguais (`text-center` é utilitário do Bootstrap, mantenha sem alteração).

- [ ] **Step 5: Verificar visualmente**

Acessar `/crm/profiles` (list de perfis) logado como admin, em tema claro e escuro (`html.theme-dark`):
- Card de filtros e card da tabela devem ter fundo/borda vindos de `var(--bg)`/`var(--outline)` (branco no claro, quase-preto no escuro), sem retângulos brancos "vazando" no tema escuro.
- Botão "Novo Perfil" deve estar com a cor `--primary` do tema atual; "Filtrar"/"Limpar" devem parecer secundários (contorno).
- Badge "Administrador" deve manter leitura clara em ambos os temas (cores de `.crm-tag--warning`, fixas — confirmar que não ficam ilegíveis no escuro).
- Hover nas linhas da tabela deve usar o tint azul de `--primary-tint`, não mais o cinza antigo.
- Paginação deve destacar a página atual com `--primary`.

- [ ] **Step 6: Commit**
```bash
git add app/views/profiles/index.html.erb app/assets/stylesheets/pages/profiles.scss app/assets/stylesheets/admin.scss
git commit -m "style(profiles): migrate profiles#index to design tokens and crm-* components"
```

---

### Task 43: Migrar `profiles/_form.html.erb` para tokens/componentes

**Files:**
- Modify: `app/assets/stylesheets/pages/profiles.scss` (criado na Task 42)
- Modify: `app/views/profiles/_form.html.erb:1-74`
- Modify: `app/assets/stylesheets/admin.scss` (confirmar require, ver Step 3)

**Interfaces:**
- Consumes: `.crm-btn`, `.crm-btn--primary`, `.crm-btn--secondary`, `.crm-input`, `.crm-label`; tokens de `tokens.scss`.
- Produces: novas classes `.profiles-form-page*` em `pages/profiles.scss`, usadas também (via partial) por `profiles/new.html.erb`, `profiles/edit.html.erb` e `profiles/show.html.erb` (read_only) sem exigir alterações nessas 3 views.

- [ ] **Step 1: Extrair o `<style>` inline para `pages/profiles.scss`**

Remover de `app/views/profiles/_form.html.erb:51-74`:

```erb
<style>
  .pform-wrapper { padding: 1.5rem 2rem; display: flex; justify-content: center; }

  .pform-card { background: #fff; border: 1px solid #e4e7f0; border-radius: 14px; box-shadow: 0 2px 12px rgba(30,40,100,0.07); width: 100%; max-width: 520px; overflow: hidden; }

  .pform-card__header { display: flex; align-items: center; gap: 1rem; padding: 1.5rem 1.75rem; border-bottom: 1px solid #f0f2f8; background: #f8f9fc; }
  .pform-card__header-icon { width: 44px; height: 44px; border-radius: 10px; background: linear-gradient(135deg, #3b4adf, #6674f5); color: #fff; display: flex; align-items: center; justify-content: center; flex-shrink: 0; }
  .pform-card__title { font-size: 1.05rem; font-weight: 700; color: #1e2235; margin: 0; }
  .pform-card__subtitle { font-size: 0.8rem; color: #9097b5; margin: 0.15rem 0 0; }

  .pform-card__body { padding: 1.75rem; display: flex; flex-direction: column; gap: 1.25rem; }

  .pform-field { display: flex; flex-direction: column; gap: 0.35rem; }
  .pform-field__label { font-size: 0.8rem; font-weight: 600; color: #5a6380; text-transform: uppercase; letter-spacing: 0.04em; }
  .pform-field__input { border: 1px solid #e4e7f0; border-radius: 8px; padding: 0.55rem 0.85rem; font-size: 0.9rem; color: #1e2235; background: #f8f9fc; outline: none; transition: border-color 0.15s, background 0.15s; width: 100%; box-sizing: border-box; }
  .pform-field__input:focus { border-color: #3b4adf; background: #fff; }

  .pform-card__footer { display: flex; align-items: center; justify-content: flex-end; gap: 0.75rem; padding: 1.25rem 1.75rem; border-top: 1px solid #f0f2f8; background: #f8f9fc; }

  .pform-btn { display: inline-flex; align-items: center; gap: 0.4rem; padding: 0.55rem 1.25rem; border-radius: 8px; font-size: 0.875rem; font-weight: 500; cursor: pointer; border: none; text-decoration: none; transition: opacity 0.15s; }
  .pform-btn:hover { opacity: 0.88; }
  .pform-btn--primary { background: #3b4adf; color: #fff; }
  .pform-btn--secondary { background: #f0f2fb; color: #3b4adf; border: 1px solid #dde1f5; }
</style>
```

Adicionar ao final de `app/assets/stylesheets/pages/profiles.scss` (mantendo o que a Task 42 já criou):

```scss
.profiles-form-page { padding: 1.5rem 2rem; display: flex; justify-content: center; }
.profiles-form-page__card { max-width: 520px; width: 100%; padding: 0; overflow: hidden; }

.profiles-form-page__header { display: flex; align-items: center; gap: 1rem; padding: 1.5rem 1.75rem; border-bottom: 1px solid var(--outline); background: var(--primary-tint); }
.profiles-form-page__header-icon { width: 44px; height: 44px; border-radius: var(--radius); background: var(--primary); color: #fff; display: flex; align-items: center; justify-content: center; flex-shrink: 0; }
.profiles-form-page__title { font-size: 1.05rem; font-weight: 700; color: var(--fg); margin: 0; }
.profiles-form-page__subtitle { font-size: 0.8rem; color: var(--fg-alt); margin: 0.15rem 0 0; }

.profiles-form-page__body { padding: 1.75rem; display: flex; flex-direction: column; gap: 1.25rem; }

.profiles-form-page__footer { display: flex; align-items: center; justify-content: flex-end; gap: 0.75rem; padding: 1.25rem 1.75rem; border-top: 1px solid var(--outline); background: var(--primary-tint); }
```

(`.pform-field`/`.pform-field__label`/`.pform-field__input` somem — viram `.crm-label`/`.crm-input` diretamente no Step 2.)

- [ ] **Step 2: Trocar classes no view**

Before (`app/views/profiles/_form.html.erb:1-49`):
```erb
<%= form_for(profile, html: { autocomplete: 'off' }, data: { disabled: read_only }) do |form| %>

  <div class="pform-wrapper">
    <div class="pform-card">

      <div class="pform-card__header">
        <div class="pform-card__header-icon">
          ...
        </div>
        <div>
          <h2 class="pform-card__title"><%= profile.new_record? ? 'Criar Perfil' : 'Editar Perfil' %></h2>
          <p class="pform-card__subtitle">Informações do perfil</p>
        </div>
      </div>

      <div class="pform-card__body">

        <div class="pform-field">
          <%= form.label :name, 'Nome', class: 'pform-field__label' %>
          <%= form.text_field :name, class: 'pform-field__input', required: true, placeholder: 'Ex: Vendedor, Gerente...' %>
        </div>

      </div>

      <div class="pform-card__footer">
        <%= link_to profiles_path, class: 'pform-btn pform-btn--secondary' do %>
          ...
          Voltar
        <% end %>
        <% unless read_only %>
          <%= form.button class: 'pform-btn pform-btn--primary',
              data: { disable_with: profile.new_record? ? 'Criando...' : 'Salvando...' } do %>
            ...
            <%= profile.new_record? ? 'Criar Perfil' : 'Salvar Alterações' %>
          <% end %>
        <% end %>
      </div>

    </div>
  </div>

<% end %>
```

After:
```erb
<%= form_for(profile, html: { autocomplete: 'off' }, data: { disabled: read_only }) do |form| %>

  <div class="profiles-form-page">
    <div class="crm-card profiles-form-page__card">

      <div class="profiles-form-page__header">
        <div class="profiles-form-page__header-icon">
          ...
        </div>
        <div>
          <h2 class="profiles-form-page__title"><%= profile.new_record? ? 'Criar Perfil' : 'Editar Perfil' %></h2>
          <p class="profiles-form-page__subtitle">Informações do perfil</p>
        </div>
      </div>

      <div class="profiles-form-page__body">

        <div>
          <%= form.label :name, 'Nome', class: 'crm-label' %>
          <%= form.text_field :name, class: 'crm-input', required: true, placeholder: 'Ex: Vendedor, Gerente...' %>
        </div>

      </div>

      <div class="profiles-form-page__footer">
        <%= link_to profiles_path, class: 'crm-btn crm-btn--secondary' do %>
          ...
          Voltar
        <% end %>
        <% unless read_only %>
          <%= form.button class: 'crm-btn crm-btn--primary',
              data: { disable_with: profile.new_record? ? 'Criando...' : 'Salvando...' } do %>
            ...
            <%= profile.new_record? ? 'Criar Perfil' : 'Salvar Alterações' %>
          <% end %>
        <% end %>
      </div>

    </div>
  </div>

<% end %>
```

- [ ] **Step 3: Confirmar require em `admin.scss`**

Se a Task 42 já rodou, `*= require pages/profiles` já está presente — nada a fazer. Se esta task está rodando isoladamente, adicione (junto com `*= require pages/users`, se ainda ausente) antes de `*= require_self`, como descrito na Task 42 Step 2.

- [ ] **Step 4: Verificar visualmente**

Acessar `/crm/profiles/new`, `/crm/profiles/:id/edit` e `/crm/profiles/:id` (show, `read_only: true`) em tema claro e escuro:
- Card centralizado deve manter largura máxima de 520px e ficar centralizado horizontalmente.
- Cabeçalho e rodapé do card com fundo levemente tintado (`--primary-tint`) — conferir contraste de texto em ambos os temas.
- No `show` (`read_only: true`), confirmar que o botão "Salvar" não aparece (mantém `data: { disabled: read_only }` e `unless read_only` intactos) e que o campo de nome fica desabilitado mas ainda legível.
- Input de nome com foco: borda e sombra devem usar `--primary`/`--primary-tint` (herdado de `.crm-input:focus`).

- [ ] **Step 5: Commit**
```bash
git add app/views/profiles/_form.html.erb app/assets/stylesheets/pages/profiles.scss
git commit -m "style(profiles): migrate profiles form partial to design tokens and crm-* components"
```

---

### Task 44: Migrar `users/index.html.erb` para tokens/componentes

**Files:**
- Create: `app/assets/stylesheets/pages/users.scss`
- Modify: `app/views/users/index.html.erb:1-194`
- Modify: `app/assets/stylesheets/admin.scss` (lista de requires)

**Interfaces:**
- Consumes: `.crm-btn`, `.crm-btn--primary`, `.crm-btn--secondary`, `.crm-input`, `.crm-label`, `.crm-table`, `.crm-tag`, `.crm-tag--success`, `.crm-tag--warning`, `.crm-tag--neutral`; tokens de `tokens.scss`.
- Produces: `app/assets/stylesheets/pages/users.scss` (também consumido pela Task 45).

**Decisões de mapeamento:**
- "Filtrar"/"Limpar" → `.crm-btn--secondary`; "Novo Usuário" → `.crm-btn--primary` (mesmo critério da Task 42).
- Badge "Admin" (perfil) → `.crm-tag--warning`. Badge de perfil comum (`badge--user`, antes azul) → `.crm-tag--neutral` (não existe variante "info" no design system atual — perde a distinção azul, ganha consistência com o resto do app).
- Badge "Configurado" (token Shopify presente) → `.crm-tag--success`. Badge "Não configurado" → `.crm-tag--warning`.
- Contador "N encontrados" → `.crm-tag--neutral`.
- Link de e-mail e link de URL Shopify não têm componente pronto — viram uma única classe de página `.users-page__link` (cor `--primary`), perdendo a distinção de cor verde que a URL Shopify tinha antes (decisão de simplificação, avisar se indesejado).

- [ ] **Step 1: Extrair o `<style>` inline para `pages/users.scss`**

Remover de `app/views/users/index.html.erb:134-195`:

```erb
<style>
  .users-wrapper { padding: 1.5rem 2rem; }

  .users-filters {
    background: #fff;
    border: 1px solid #e4e7f0;
    border-radius: 10px;
    padding: 1.1rem 1.5rem;
    margin-bottom: 1.5rem;
    box-shadow: 0 1px 4px rgba(0,0,0,0.05);
  }
  .users-filters__row { display: flex; flex-wrap: wrap; gap: 0.85rem; align-items: flex-end; }
  .users-filters__field { display: flex; flex-direction: column; gap: 0.3rem; flex: 1; min-width: 200px; }
  .users-filters__field label { font-size: 0.78rem; font-weight: 600; color: #5a6380; text-transform: uppercase; letter-spacing: 0.04em; }
  .users-filters__input { border: 1px solid #e4e7f0; border-radius: 8px; padding: 0.5rem 0.75rem; font-size: 0.875rem; color: #1e2235; background: #f8f9fc; outline: none; transition: border-color 0.15s; }
  .users-filters__input:focus { border-color: #3b4adf; background: #fff; }
  .users-filters__actions { display: flex; gap: 0.5rem; align-items: flex-end; }

  .users-btn { display: inline-flex; align-items: center; gap: 0.4rem; padding: 0.5rem 1rem; border-radius: 8px; font-size: 0.875rem; font-weight: 500; cursor: pointer; border: none; text-decoration: none; transition: opacity 0.15s; }
  .users-btn:hover { opacity: 0.88; }
  .users-btn--primary { background: #3b4adf; color: #fff; }
  .users-btn--secondary { background: #f0f2fb; color: #3b4adf; border: 1px solid #dde1f5; }
  .users-btn--success { background: #1d7a3e; color: #fff; }
  .users-btn--icon { background: #f0f2fb; color: #3b4adf; border: 1px solid #dde1f5; padding: 0.4rem 0.75rem; font-size: 0.82rem; }

  .users-table-wrap { background: #fff; border: 1px solid #e4e7f0; border-radius: 12px; box-shadow: 0 1px 4px rgba(0,0,0,0.05); overflow: hidden; }
  .users-table-header { display: flex; align-items: center; justify-content: space-between; padding: 1rem 1.5rem; border-bottom: 1px solid #f0f2f8; }
  .users-table-header__title { display: flex; align-items: center; gap: 0.5rem; font-weight: 600; color: #1e2235; font-size: 0.95rem; }
  .users-table-header__count { font-size: 0.8rem; color: #9097b5; background: #f4f5fb; padding: 0.25rem 0.65rem; border-radius: 20px; }

  .users-table { width: 100%; border-collapse: collapse; }
  .users-table thead th { padding: 0.75rem 1.25rem; font-size: 0.75rem; font-weight: 700; color: #9097b5; text-transform: uppercase; letter-spacing: 0.06em; background: #f8f9fc; border-bottom: 1px solid #e4e7f0; white-space: nowrap; }
  .users-table tbody td { padding: 0.9rem 1.25rem; border-bottom: 1px solid #f0f2f8; font-size: 0.875rem; color: #3a4060; vertical-align: middle; }
  .users-table tbody tr:last-child td { border-bottom: none; }
  .users-table tbody tr:hover td { background: #f8f9fc; }
  .users-table tfoot td { padding: 0.75rem 1.25rem; font-size: 0.8rem; color: #9097b5; border-top: 1px solid #f0f2f8; }
  .users-table__empty { text-align: center; color: #9097b5; padding: 3rem !important; }

  .users-table__user { display: flex; align-items: center; gap: 0.75rem; }
  .users-table__avatar { width: 36px; height: 36px; border-radius: 50%; background: linear-gradient(135deg, #3b4adf, #6674f5); color: #fff; font-size: 0.8rem; font-weight: 700; display: flex; align-items: center; justify-content: center; flex-shrink: 0; }
  .users-table__name { font-weight: 600; color: #1e2235; }
  .users-table__id { font-size: 0.75rem; color: #9097b5; }
  .users-table__email { color: #3b4adf; text-decoration: none; font-size: 0.875rem; }
  .users-table__email:hover { text-decoration: underline; }
  .users-table__date { color: #6b7280; font-size: 0.82rem; white-space: nowrap; }

  .users-table__shopify-url { color: #5e8e3e; text-decoration: none; font-size: 0.82rem; font-family: monospace; }
  .users-table__shopify-url:hover { text-decoration: underline; }
  .users-table__empty-field { color: #c5c9db; font-size: 0.875rem; }

  .users-table__badge { display: inline-flex; align-items: center; gap: 0.3rem; padding: 0.2rem 0.65rem; border-radius: 20px; font-size: 0.75rem; font-weight: 600; }
  .users-table__badge--admin { background: #fef3c7; color: #92400e; }
  .users-table__badge--user { background: #eff6ff; color: #1d4ed8; }
  .users-table__badge--shopify { background: #d1fae5; color: #065f46; }
  .users-table__badge--pending { background: #fef3c7; color: #92400e; }

  .users-pagination { display: flex; list-style: none; gap: 0.4rem; padding: 1rem 1.5rem; margin: 0; justify-content: center; }
  .users-pagination li a, .users-pagination li span { display: inline-flex; align-items: center; justify-content: center; min-width: 32px; height: 32px; padding: 0 0.5rem; border-radius: 6px; font-size: 0.82rem; font-weight: 500; border: 1px solid #e4e7f0; color: #3a4060; text-decoration: none; transition: all 0.15s; }
  .users-pagination li.current span { background: #3b4adf; color: #fff; border-color: #3b4adf; }
  .users-pagination li a:hover { background: #f0f2fb; border-color: #b0b8f0; }
  .text-center { text-align: center; }
</style>
```

Criar `app/assets/stylesheets/pages/users.scss`:

```scss
.users-page { padding: 1.5rem 2rem; }

.users-page__filters-row-wrap { margin-bottom: 1.5rem; }
.users-page__filters-row { display: flex; flex-wrap: wrap; gap: 0.85rem; align-items: flex-end; }
.users-page__filters-field { display: flex; flex-direction: column; gap: 0.3rem; flex: 1; min-width: 200px; }
.users-page__filters-actions { display: flex; gap: 0.5rem; align-items: flex-end; }

.users-page__table-wrap { padding: 0; overflow: hidden; }
.users-page__table-header { display: flex; align-items: center; justify-content: space-between; padding: 1rem 1.5rem; border-bottom: 1px solid var(--outline); }
.users-page__table-title { display: flex; align-items: center; gap: 0.5rem; font-weight: 600; color: var(--fg); font-size: 0.95rem; }
.users-page__table-wrap tfoot td { color: var(--fg-alt); font-size: 0.8rem; }

.users-page__user { display: flex; align-items: center; gap: 0.75rem; }
.users-page__avatar { width: 36px; height: 36px; border-radius: 50%; background: var(--primary); color: #fff; font-size: 0.8rem; font-weight: 700; display: flex; align-items: center; justify-content: center; flex-shrink: 0; }
.users-page__name { font-weight: 600; color: var(--fg); }
.users-page__id { font-size: 0.75rem; color: var(--fg-alt); }
.users-page__date { color: var(--fg-alt); font-size: 0.82rem; white-space: nowrap; }

.users-page__link { color: var(--primary); text-decoration: none; font-size: 0.875rem; }
.users-page__link:hover { text-decoration: underline; }
.users-page__empty-field { color: var(--fg-alt); font-size: 0.875rem; }
.users-page__empty { text-align: center; color: var(--fg-alt); padding: 3rem !important; }

.users-page__pagination { display: flex; list-style: none; gap: 0.4rem; padding: 1rem 1.5rem; margin: 0; justify-content: center; }
.users-page__pagination li a, .users-page__pagination li span { display: inline-flex; align-items: center; justify-content: center; min-width: 32px; height: 32px; padding: 0 0.5rem; border-radius: var(--radius); font-size: 0.82rem; font-weight: 500; border: 1px solid var(--outline); color: var(--fg); text-decoration: none; transition: all 0.15s; }
.users-page__pagination li.current span { background: var(--primary); color: #fff; border-color: var(--primary); }
.users-page__pagination li a:hover { background: var(--primary-tint); border-color: var(--primary); }
```

- [ ] **Step 2: Registrar o require em `admin.scss`**

Igual à Task 42 Step 2 — confirmar (ou adicionar) `*= require pages/profiles` e `*= require pages/users` antes de `*= require_self`. Idempotente: se a Task 42 já rodou, só falta garantir que `pages/users` está lá agora que o arquivo existe.

- [ ] **Step 3: Trocar classes do bloco de filtros**

Padrão idêntico ao da Task 42 Step 3 (mesmos nomes de botão/label/input), trocando o prefixo `profiles-` por `users-` e o texto "Novo Perfil" por "Novo Usuário":

Before (`app/views/users/index.html.erb:3-35`):
```erb
<div class="users-wrapper">
  ...
  <%= form_tag(users_path, method: 'get') do %>
    <div class="users-filters">
      <div class="users-filters__row">
        <div class="users-filters__field">
          <label>Buscar</label>
          <%= text_field_tag :search, params[:search], class: 'users-filters__input', placeholder: 'Nome ou e-mail...' %>
        </div>
        <div class="users-filters__actions">
          <%= button_tag class: 'users-btn users-btn--primary', name: '' do %>
            ...Filtrar<% end %>
          <%= link_to users_path, class: 'users-btn users-btn--secondary' do %>
            ...Limpar<% end %>
          <%= link_to new_user_path, class: 'users-btn users-btn--success' do %>
            ...Novo Usuário<% end %>
        </div>
      </div>
    </div>
  <% end %>
```

After:
```erb
<div class="users-page">
  ...
  <%= form_tag(users_path, method: 'get') do %>
    <div class="crm-card users-page__filters-row-wrap">
      <div class="users-page__filters-row">
        <div class="users-page__filters-field">
          <label class="crm-label">Buscar</label>
          <%= text_field_tag :search, params[:search], class: 'crm-input', placeholder: 'Nome ou e-mail...' %>
        </div>
        <div class="users-page__filters-actions">
          <%= button_tag class: 'crm-btn crm-btn--secondary', name: '' do %>
            ...Filtrar<% end %>
          <%= link_to users_path, class: 'crm-btn crm-btn--secondary' do %>
            ...Limpar<% end %>
          <%= link_to new_user_path, class: 'crm-btn crm-btn--primary' do %>
            ...Novo Usuário<% end %>
        </div>
      </div>
    </div>
  <% end %>
```

- [ ] **Step 4: Trocar classes da tabela, badges e paginação**

Before (`app/views/users/index.html.erb:38-133`, trechos relevantes):
```erb
  <div class="users-table-wrap">
    <div class="users-table-header">
      <span class="users-table-header__title">
        ...Usuários
      </span>
      <span class="users-table-header__count"><%= @users.total_entries rescue @users.count %> encontrados</span>
    </div>

    <table class="users-table">
```
```erb
              <div class="users-table__user">
                <div class="users-table__avatar"><%= initials.presence || '?' %></div>
                <div>
                  <div class="users-table__name"><%= user.name %></div>
                  <div class="users-table__id">ID #<%= user.id %></div>
                </div>
              </div>
            </td>
            <td>
              <a href="mailto:<%= user.email %>" class="users-table__email"><%= user.email %></a>
            </td>
            <td>
              <% if user.admin? %>
                <span class="users-table__badge users-table__badge--admin">Admin</span>
              <% else %>
                <span class="users-table__badge users-table__badge--user"><%= user.try(:profile)&.name || 'Usuário' %></span>
              <% end %>
            </td>
            <td>
              <% if user.client&.shopify_shop_url.present? %>
                <a href="<%= user.client.shopify_shop_url %>" target="_blank" class="users-table__shopify-url">
                  <%= user.client.shopify_shop_url.gsub(/https?:\/\//, '').truncate(30) %>
                </a>
              <% else %>
                <span class="users-table__empty-field">—</span>
              <% end %>
            </td>
            <td>
              <% if user.client&.shopify_access_token.present? %>
                <span class="users-table__badge users-table__badge--shopify">
                  ...
                  Configurado
                </span>
              <% else %>
                <span class="users-table__badge users-table__badge--pending">Não configurado</span>
              <% end %>
            </td>
```
```erb
              <%= link_to edit_user_path(user), class: 'users-btn users-btn--icon' do %>
```
```erb
            <td colspan="7" class="users-table__empty">Nenhum usuário encontrado.</td>
```
```erb
    <%= will_paginate @users, list_classes: %w[users-pagination] %>
  </div>

</div>
```

After:
```erb
  <div class="crm-card users-page__table-wrap">
    <div class="users-page__table-header">
      <span class="users-page__table-title">
        ...Usuários
      </span>
      <span class="crm-tag crm-tag--neutral"><%= @users.total_entries rescue @users.count %> encontrados</span>
    </div>

    <table class="crm-table">
```
```erb
              <div class="users-page__user">
                <div class="users-page__avatar"><%= initials.presence || '?' %></div>
                <div>
                  <div class="users-page__name"><%= user.name %></div>
                  <div class="users-page__id">ID #<%= user.id %></div>
                </div>
              </div>
            </td>
            <td>
              <a href="mailto:<%= user.email %>" class="users-page__link"><%= user.email %></a>
            </td>
            <td>
              <% if user.admin? %>
                <span class="crm-tag crm-tag--warning">Admin</span>
              <% else %>
                <span class="crm-tag crm-tag--neutral"><%= user.try(:profile)&.name || 'Usuário' %></span>
              <% end %>
            </td>
            <td>
              <% if user.client&.shopify_shop_url.present? %>
                <a href="<%= user.client.shopify_shop_url %>" target="_blank" class="users-page__link">
                  <%= user.client.shopify_shop_url.gsub(/https?:\/\//, '').truncate(30) %>
                </a>
              <% else %>
                <span class="users-page__empty-field">—</span>
              <% end %>
            </td>
            <td>
              <% if user.client&.shopify_access_token.present? %>
                <span class="crm-tag crm-tag--success">
                  ...
                  Configurado
                </span>
              <% else %>
                <span class="crm-tag crm-tag--warning">Não configurado</span>
              <% end %>
            </td>
```
```erb
              <%= link_to edit_user_path(user), class: 'crm-btn crm-btn--secondary' do %>
```
```erb
            <td colspan="7" class="users-page__empty">Nenhum usuário encontrado.</td>
```
```erb
    <%= will_paginate @users, list_classes: %w[users-page__pagination] %>
  </div>

</div>
```

- [ ] **Step 5: Verificar visualmente**

Acessar `/crm/users` em tema claro e escuro:
- Avatar circular deve usar `--primary` sólido (perdeu o gradiente antigo — confirmar que fica legível/aceitável).
- Badges "Admin", perfil comum, "Configurado" e "Não configurado" devem estar visualmente distintos o suficiente mesmo tendo perfil comum e "Não configurado" reaproveitando `--neutral`/`--warning` (não há variante "info" — badge de perfil comum perde a cor azul original).
- Links de e-mail e de URL Shopify devem usar a mesma cor `--primary` (perderam a distinção verde/azul original — confirmar que isso é aceitável ou pedir variante nova).
- Coluna "Shopify Token" com célula vazia (`—`) deve ficar visivelmente apagada (`--fg-alt`) em ambos os temas.

- [ ] **Step 6: Commit**
```bash
git add app/views/users/index.html.erb app/assets/stylesheets/pages/users.scss app/assets/stylesheets/admin.scss
git commit -m "style(users): migrate users#index to design tokens and crm-* components"
```

---

### Task 45: Migrar `users/_form.html.erb` para tokens/componentes

**Files:**
- Modify: `app/assets/stylesheets/pages/users.scss` (criado na Task 44)
- Modify: `app/views/users/_form.html.erb:1-184`
- Modify: `app/assets/stylesheets/admin.scss` (confirmar require, ver Step 4)

**Interfaces:**
- Consumes: `.crm-btn`, `.crm-btn--primary`, `.crm-btn--secondary`, `.crm-input`, `.crm-label`, `.crm-tag--success`, `.crm-tag--warning`; tokens de `tokens.scss`.
- Produces: novas classes `.users-form-page*` em `pages/users.scss`, usadas também (via partial) por `users/new.html.erb` e `users/edit.html.erb` sem exigir alterações nessas 2 views.

**Decisões de mapeamento:**
- Badges "Configurado"/"Não configurado" dentro do bloco readonly Shopify → reaproveita `.crm-tag--success` / `.crm-tag--warning` (igual à Task 44).
- Bloco de erros de validação (`uform-errors`) não tem componente "alert" no design system atual — vira uma classe de página própria (`.users-form-page__errors`) reaproveitando a mesma paleta vermelha de `.crm-tag--danger` (`#fce8e6`/`#c5221f`) para manter consistência, mesmo sem usar o componente de tag diretamente.
- O `<select>` de Perfil/Cliente (`collection_select`) recebe `.crm-input` normalmente, mas mantém uma classe modificadora `.users-form-page__select` só para a seta customizada (background-image SVG); a cor do traço da seta fica fixa em `#6a6f71` (aprox. de `--fg-alt` no tema claro) porque um `data:` URI não lê custom properties — no tema escuro a seta fica ligeiramente menos contrastante. Ver nota na Step 4.

- [ ] **Step 1: Extrair o `<style>` inline para `pages/users.scss`**

Remover de `app/views/users/_form.html.erb:137-185`:

```erb
<style>
  .uform-wrapper { padding: 1.5rem 2rem; display: flex; justify-content: center; }

  .uform-card { background: #fff; border: 1px solid #e4e7f0; border-radius: 14px; box-shadow: 0 2px 12px rgba(30,40,100,0.07); width: 100%; overflow: hidden; }

  .uform-card__header { display: flex; align-items: center; gap: 1rem; padding: 1.5rem 1.75rem; border-bottom: 1px solid #f0f2f8; background: #f8f9fc; }
  .uform-card__header-icon { width: 44px; height: 44px; border-radius: 10px; background: linear-gradient(135deg, #3b4adf, #6674f5); color: #fff; display: flex; align-items: center; justify-content: center; flex-shrink: 0; }
  .uform-card__title { font-size: 1.05rem; font-weight: 700; color: #1e2235; margin: 0; }
  .uform-card__subtitle { font-size: 0.8rem; color: #9097b5; margin: 0.15rem 0 0; }

  .uform-errors { display: flex; align-items: flex-start; gap: 0.75rem; padding: 1rem 1.5rem; background: #fef2f2; border-bottom: 1px solid #fecaca; color: #991b1b; font-size: 0.85rem; }
  .uform-errors__icon { flex-shrink: 0; color: #dc2626; }
  .uform-errors ul { margin: 0.5rem 0 0 1rem; padding: 0; }
  .uform-errors li { margin: 0.25rem 0; }

  .uform-card__body { padding: 1.75rem; display: flex; flex-direction: column; gap: 1.25rem; }

  .uform-row { display: grid; grid-template-columns: 1fr 1fr; gap: 1rem; }
  @media (max-width: 520px) { .uform-row { grid-template-columns: 1fr; } }

  .uform-field { display: flex; flex-direction: column; gap: 0.35rem; }
  .uform-field__label { font-size: 0.8rem; font-weight: 600; color: #5a6380; text-transform: uppercase; letter-spacing: 0.04em; }
  .uform-field__input { border: 1px solid #e4e7f0; border-radius: 8px; padding: 0.55rem 0.85rem; font-size: 0.9rem; color: #1e2235; background: #f8f9fc; outline: none; transition: border-color 0.15s, background 0.15s; width: 100%; box-sizing: border-box; }
  .uform-field__input:focus { border-color: #3b4adf; background: #fff; }
  .uform-field__input--select { appearance: none; background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='12' fill='none' viewBox='0 0 24 24' stroke='%239097b5' stroke-width='2'%3E%3Cpath stroke-linecap='round' stroke-linejoin='round' d='M19 9l-7 7-7-7'/%3E%3C/svg%3E"); background-repeat: no-repeat; background-position: right 0.85rem center; padding-right: 2.5rem; cursor: pointer; }

  .uform-field__readonly { padding: 0.55rem 0.85rem; background: #f0f2f8; border-radius: 8px; font-size: 0.85rem; color: #5a6380; min-height: 38px; display: flex; align-items: center; }
  .uform-field__readonly a { color: #3b4adf; text-decoration: none; }
  .uform-field__readonly a:hover { text-decoration: underline; }
  .uform-field__empty { color: #9097b5; font-style: italic; }

  .uform-field__badge { display: inline-flex; align-items: center; padding: 0.2rem 0.65rem; border-radius: 20px; font-size: 0.75rem; font-weight: 600; }
  .uform-field__badge--success { background: #d1fae5; color: #065f46; }
  .uform-field__badge--warning { background: #fef3c7; color: #92400e; }

  .uform-section { background: #f8f9fc; border: 1px solid #e4e7f0; border-radius: 10px; padding: 1.25rem; margin-top: 0.5rem; }
  .uform-section__header { display: flex; align-items: center; gap: 0.5rem; font-weight: 600; font-size: 0.9rem; color: #1e2235; margin-bottom: 1rem; }
  .uform-section__hint { font-size: 0.78rem; color: #9097b5; margin-top: 1rem; margin-bottom: 0; }

  .uform-link { color: #3b4adf; text-decoration: none; font-weight: 500; }
  .uform-link:hover { text-decoration: underline; }

  .uform-card__footer { display: flex; align-items: center; justify-content: flex-end; gap: 0.75rem; padding: 1.25rem 1.75rem; border-top: 1px solid #f0f2f8; background: #f8f9fc; }

  .uform-btn { display: inline-flex; align-items: center; gap: 0.4rem; padding: 0.55rem 1.25rem; border-radius: 8px; font-size: 0.875rem; font-weight: 500; cursor: pointer; border: none; text-decoration: none; transition: opacity 0.15s; }
  .uform-btn:hover { opacity: 0.88; }
  .uform-btn--primary { background: #3b4adf; color: #fff; }
  .uform-btn--secondary { background: #f0f2fb; color: #3b4adf; border: 1px solid #dde1f5; }
</style>
```

Adicionar ao final de `app/assets/stylesheets/pages/users.scss` (mantendo o que a Task 44 já criou):

```scss
.users-form-page { padding: 1.5rem 2rem; display: flex; justify-content: center; }
.users-form-page__card { width: 100%; padding: 0; overflow: hidden; }

.users-form-page__header { display: flex; align-items: center; gap: 1rem; padding: 1.5rem 1.75rem; border-bottom: 1px solid var(--outline); background: var(--primary-tint); }
.users-form-page__header-icon { width: 44px; height: 44px; border-radius: var(--radius); background: var(--primary); color: #fff; display: flex; align-items: center; justify-content: center; flex-shrink: 0; }
.users-form-page__title { font-size: 1.05rem; font-weight: 700; color: var(--fg); margin: 0; }
.users-form-page__subtitle { font-size: 0.8rem; color: var(--fg-alt); margin: 0.15rem 0 0; }

.users-form-page__errors { display: flex; align-items: flex-start; gap: 0.75rem; padding: 1rem 1.5rem; background: #fce8e6; border-bottom: 1px solid #f6b3ae; color: #c5221f; font-size: 0.85rem; }
.users-form-page__errors-icon { flex-shrink: 0; color: #c5221f; }
.users-form-page__errors ul { margin: 0.5rem 0 0 1rem; padding: 0; }
.users-form-page__errors li { margin: 0.25rem 0; }

.users-form-page__body { padding: 1.75rem; display: flex; flex-direction: column; gap: 1.25rem; }

.users-form-page__row { display: grid; grid-template-columns: 1fr 1fr; gap: 1rem; }
@media (max-width: 520px) { .users-form-page__row { grid-template-columns: 1fr; } }

.users-form-page__field { display: flex; flex-direction: column; gap: 0.35rem; }
.users-form-page__select { appearance: none; background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='12' fill='none' viewBox='0 0 24 24' stroke='%236a6f71' stroke-width='2'%3E%3Cpath stroke-linecap='round' stroke-linejoin='round' d='M19 9l-7 7-7-7'/%3E%3C/svg%3E"); background-repeat: no-repeat; background-position: right 0.85rem center; padding-right: 2.5rem; cursor: pointer; }

.users-form-page__readonly { padding: 0.55rem 0.85rem; background: var(--primary-tint); border-radius: var(--radius); font-size: 0.85rem; color: var(--fg-alt); min-height: 38px; display: flex; align-items: center; }
.users-form-page__readonly a { color: var(--primary); text-decoration: none; }
.users-form-page__readonly a:hover { text-decoration: underline; }
.users-form-page__empty { color: var(--fg-alt); font-style: italic; }

.users-form-page__section { background: var(--primary-tint); border: 1px solid var(--outline); border-radius: var(--radius); padding: 1.25rem; margin-top: 0.5rem; }
.users-form-page__section-header { display: flex; align-items: center; gap: 0.5rem; font-weight: 600; font-size: 0.9rem; color: var(--fg); margin-bottom: 1rem; }
.users-form-page__section-hint { font-size: 0.78rem; color: var(--fg-alt); margin-top: 1rem; margin-bottom: 0; }

.users-form-page__link { color: var(--primary); text-decoration: none; font-weight: 500; }
.users-form-page__link:hover { text-decoration: underline; }

.users-form-page__footer { display: flex; align-items: center; justify-content: flex-end; gap: 0.75rem; padding: 1.25rem 1.75rem; border-top: 1px solid var(--outline); background: var(--primary-tint); }
```

- [ ] **Step 2: Trocar classes do cabeçalho, erros e campos simples**

Before (`app/views/users/_form.html.erb:1-46`):
```erb
<%= form_for(user, as: :user, html: { autocomplete: 'off' }, data: { disabled: read_only }) do |form| %>

  <div class="uform-wrapper">
    <div class="uform-card">

      <div class="uform-card__header">
        <div class="uform-card__header-icon">
          ...
        </div>
        <div>
          <h2 class="uform-card__title"><%= user.new_record? ? 'Criar Usuário' : 'Editar Usuário' %></h2>
          <p class="uform-card__subtitle">Informações do usuário</p>
        </div>
      </div>

      <% if user.errors.any? %>
        <div class="uform-errors">
          <div class="uform-errors__icon">
            ...
          </div>
          <div>
            <strong>Corrija os erros abaixo:</strong>
            <ul>
              <% user.errors.full_messages.each do |msg| %>
                <li><%= msg %></li>
              <% end %>
            </ul>
          </div>
        </div>
      <% end %>

      <div class="uform-card__body">

        <div class="uform-field">
          <%= form.label :name, 'Nome', class: 'uform-field__label' %>
          <%= form.text_field :name, class: 'uform-field__input', required: true, placeholder: 'Nome completo' %>
        </div>

        <div class="uform-field">
          <%= form.label :email, 'E-mail', class: 'uform-field__label' %>
          <%= form.email_field :email, class: 'uform-field__input', required: true, placeholder: 'email@exemplo.com' %>
        </div>
```

After:
```erb
<%= form_for(user, as: :user, html: { autocomplete: 'off' }, data: { disabled: read_only }) do |form| %>

  <div class="users-form-page">
    <div class="crm-card users-form-page__card">

      <div class="users-form-page__header">
        <div class="users-form-page__header-icon">
          ...
        </div>
        <div>
          <h2 class="users-form-page__title"><%= user.new_record? ? 'Criar Usuário' : 'Editar Usuário' %></h2>
          <p class="users-form-page__subtitle">Informações do usuário</p>
        </div>
      </div>

      <% if user.errors.any? %>
        <div class="users-form-page__errors">
          <div class="users-form-page__errors-icon">
            ...
          </div>
          <div>
            <strong>Corrija os erros abaixo:</strong>
            <ul>
              <% user.errors.full_messages.each do |msg| %>
                <li><%= msg %></li>
              <% end %>
            </ul>
          </div>
        </div>
      <% end %>

      <div class="users-form-page__body">

        <div class="users-form-page__field">
          <%= form.label :name, 'Nome', class: 'crm-label' %>
          <%= form.text_field :name, class: 'crm-input', required: true, placeholder: 'Nome completo' %>
        </div>

        <div class="users-form-page__field">
          <%= form.label :email, 'E-mail', class: 'crm-label' %>
          <%= form.email_field :email, class: 'crm-input', required: true, placeholder: 'email@exemplo.com' %>
        </div>
```

- [ ] **Step 3: Trocar classes dos campos de senha, selects e bloco readonly Shopify**

Before (`app/views/users/_form.html.erb:48-110`):
```erb
        <% if user.new_record? %>
          <div class="uform-row">
            <div class="uform-field">
              <%= form.label :password, 'Senha', class: 'uform-field__label' %>
              <%= form.password_field :password, class: 'uform-field__input', required: true, placeholder: 'Mínimo 6 caracteres' %>
            </div>
            <div class="uform-field">
              <%= form.label :password_confirmation, 'Confirmar Senha', class: 'uform-field__label' %>
              <%= form.password_field :password_confirmation, class: 'uform-field__input', required: true, placeholder: 'Repita a senha' %>
            </div>
          </div>
        <% end %>

        <div class="uform-row">
          <div class="uform-field">
            <%= form.label :profile_id, 'Perfil', class: 'uform-field__label' %>
            <%= form.collection_select :profile_id, @profiles || [], :id, :name,
                { include_blank: 'Selecione um perfil' },
                { class: 'uform-field__input uform-field__input--select' } %>
          </div>
          <div class="uform-field">
            <%= form.label :client_id, 'Cliente', class: 'uform-field__label' %>
            <%= form.collection_select :client_id, @clients || [], :id, :name,
                { include_blank: 'Selecione um cliente' },
                { class: 'uform-field__input uform-field__input--select' } %>
          </div>
        </div>

        <% if user.client.present? %>
          <div class="uform-section">
            <div class="uform-section__header">
              ...
              Configurações Shopify do Cliente: <%= user.client.name %>
            </div>
            <div class="uform-row">
              <div class="uform-field">
                <label class="uform-field__label">URL da Loja</label>
                <div class="uform-field__readonly">
                  <% if user.client.shopify_shop_url.present? %>
                    <a href="<%= user.client.shopify_shop_url %>" target="_blank"><%= user.client.shopify_shop_url %></a>
                  <% else %>
                    <span class="uform-field__empty">Não configurado</span>
                  <% end %>
                </div>
              </div>
              <div class="uform-field">
                <label class="uform-field__label">Token de Acesso</label>
                <div class="uform-field__readonly">
                  <% if user.client.shopify_access_token.present? %>
                    <span class="uform-field__badge uform-field__badge--success">Configurado</span>
                  <% else %>
                    <span class="uform-field__badge uform-field__badge--warning">Não configurado</span>
                  <% end %>
                </div>
              </div>
            </div>
            <p class="uform-section__hint">
              Para editar as configurações Shopify, <%= link_to 'edite o cliente', edit_client_path(user.client), class: 'uform-link' %>.
            </p>
          </div>
        <% end %>

      </div>
```

After:
```erb
        <% if user.new_record? %>
          <div class="users-form-page__row">
            <div class="users-form-page__field">
              <%= form.label :password, 'Senha', class: 'crm-label' %>
              <%= form.password_field :password, class: 'crm-input', required: true, placeholder: 'Mínimo 6 caracteres' %>
            </div>
            <div class="users-form-page__field">
              <%= form.label :password_confirmation, 'Confirmar Senha', class: 'crm-label' %>
              <%= form.password_field :password_confirmation, class: 'crm-input', required: true, placeholder: 'Repita a senha' %>
            </div>
          </div>
        <% end %>

        <div class="users-form-page__row">
          <div class="users-form-page__field">
            <%= form.label :profile_id, 'Perfil', class: 'crm-label' %>
            <%= form.collection_select :profile_id, @profiles || [], :id, :name,
                { include_blank: 'Selecione um perfil' },
                { class: 'crm-input users-form-page__select' } %>
          </div>
          <div class="users-form-page__field">
            <%= form.label :client_id, 'Cliente', class: 'crm-label' %>
            <%= form.collection_select :client_id, @clients || [], :id, :name,
                { include_blank: 'Selecione um cliente' },
                { class: 'crm-input users-form-page__select' } %>
          </div>
        </div>

        <% if user.client.present? %>
          <div class="users-form-page__section">
            <div class="users-form-page__section-header">
              ...
              Configurações Shopify do Cliente: <%= user.client.name %>
            </div>
            <div class="users-form-page__row">
              <div class="users-form-page__field">
                <label class="crm-label">URL da Loja</label>
                <div class="users-form-page__readonly">
                  <% if user.client.shopify_shop_url.present? %>
                    <a href="<%= user.client.shopify_shop_url %>" target="_blank"><%= user.client.shopify_shop_url %></a>
                  <% else %>
                    <span class="users-form-page__empty">Não configurado</span>
                  <% end %>
                </div>
              </div>
              <div class="users-form-page__field">
                <label class="crm-label">Token de Acesso</label>
                <div class="users-form-page__readonly">
                  <% if user.client.shopify_access_token.present? %>
                    <span class="crm-tag crm-tag--success">Configurado</span>
                  <% else %>
                    <span class="crm-tag crm-tag--warning">Não configurado</span>
                  <% end %>
                </div>
              </div>
            </div>
            <p class="users-form-page__section-hint">
              Para editar as configurações Shopify, <%= link_to 'edite o cliente', edit_client_path(user.client), class: 'users-form-page__link' %>.
            </p>
          </div>
        <% end %>

      </div>
```

- [ ] **Step 4: Trocar classes do rodapé**

Before (`app/views/users/_form.html.erb:114-133`):
```erb
      <div class="uform-card__footer">
        <%= link_to users_path, class: 'uform-btn uform-btn--secondary' do %>
          ...Voltar<% end %>
        <% unless read_only %>
          <%= form.button class: 'uform-btn uform-btn--primary',
              data: { disable_with: user.new_record? ? 'Criando...' : 'Salvando...' } do %>
            ...
            <%= user.new_record? ? 'Criar Usuário' : 'Salvar Alterações' %>
          <% end %>
        <% end %>
      </div>
```

After:
```erb
      <div class="users-form-page__footer">
        <%= link_to users_path, class: 'crm-btn crm-btn--secondary' do %>
          ...Voltar<% end %>
        <% unless read_only %>
          <%= form.button class: 'crm-btn crm-btn--primary',
              data: { disable_with: user.new_record? ? 'Criando...' : 'Salvando...' } do %>
            ...
            <%= user.new_record? ? 'Criar Usuário' : 'Salvar Alterações' %>
          <% end %>
        <% end %>
      </div>
```

Nota: `users/_form.html.erb` é sempre chamado com `read_only: false` (ver `users/new.html.erb` e `users/edit.html.erb`), então o ramo `read_only` nunca oculta o botão de salvar hoje — mantenha o comportamento exatamente como está, só trocando classes.

- [ ] **Step 5: Confirmar require em `admin.scss`**

Igual à Task 44 Step 2 — nada a fazer se `pages/users` já foi adicionado antes; caso contrário adicionar `*= require pages/users` (e `*= require pages/profiles`, se ausente) antes de `*= require_self`.

- [ ] **Step 6: Verificar visualmente**

Acessar `/crm/users/new` e `/crm/users/:id/edit` (escolher um usuário com `client` associado a um Shopify configurado e outro sem) em tema claro e escuro:
- Bloco de erros de validação (submeter formulário vazio) deve ficar legível em ambos os temas com a paleta vermelha fixa.
- Grid de 2 colunas (`users-form-page__row`) deve colapsar para 1 coluna em telas < 520px.
- Seta do `<select>` de Perfil/Cliente deve estar visível tanto no claro quanto no escuro (checar se o traço fixo `#6a6f71` some no fundo escuro — se sim, é o caveat já registrado acima).
- Bloco "Configurações Shopify do Cliente" com badges "Configurado"/"Não configurado" reaproveitando as cores de `.crm-tag--success`/`.crm-tag--warning`.

- [ ] **Step 7: Commit**
```bash
git add app/views/users/_form.html.erb app/assets/stylesheets/pages/users.scss
git commit -m "style(users): migrate users form partial to design tokens and crm-* components"
```

---

### Task 46: Migrar `attempts/index.html.erb` e `attempts/verify_attempts.html.erb` para componentes `.crm-*`

**Files:**
- Modify: `app/views/attempts/index.html.erb:1-89`
- Modify: `app/views/attempts/verify_attempts.html.erb:1-84`

**Interfaces:**
- Consumes: `.crm-card`, `.crm-btn`, `.crm-btn--primary`, `.crm-btn--secondary`, `.crm-input`, `.crm-label`, `.crm-table`, `.crm-tag`, `.crm-tag--success`, `.crm-tag--danger`, `.crm-tag--warning`, `.crm-tag--neutral`; tokens de `tokens.scss`. Nenhum `<style>` inline existia nessas views, então nenhuma extração de CSS/arquivo `pages/*.scss` é necessária aqui.
- Produces: nada novo (não é reusado por outra view).

**Atenção (dependência de JS/DataTables):** `attempts/verify_attempts.html.erb:57` roda `$('.table').DataTable();` — o seletor depende da classe Bootstrap `table` continuar presente na `<table id="attemps-table">`. Ao trocar as classes visuais dessa tabela específica, **mantenha a classe `table` junto com `crm-table`** (`class="table crm-table"`). Já `attempts/index.html.erb` não inicializa DataTables (usa `will_paginate`), então lá a classe `table`/`table-dark`/`table-hover`/`table-responsive` pode ser totalmente removida e substituída por `crm-table` sem risco.

- [ ] **Step 1: `attempts/index.html.erb` — bloco de filtro por status (topo)**

Before (`app/views/attempts/index.html.erb:5-11`):
```erb
<div class="row d-flex justify-content-center">
  <div class="btn-group mb-3" role="group">
    <%= link_to attempts_path(kinds: params[:kinds], status: :success, search: params[:search]), class: 'btn btn-success text-light' do %> success <i class="fas fa-check"></i><% end %>
    <%= link_to attempts_path(kinds: params[:kinds], status: :fail, search: params[:search]), class: 'btn btn-danger text-light' do %> fail <i class="fas fa-times"></i><% end %>
    <%= link_to attempts_path(kinds: params[:kinds], status: :error, search: params[:search]), class: 'btn btn-secondary text-light' do %> error <i class="fa-solid fa-wrench"></i><% end %>
  </div>
</div>
```

After (link de status vira um "chip" clicável reaproveitando `.crm-tag` com as variantes semânticas equivalentes — success/danger/warning):
```erb
<div class="d-flex justify-content-center gap-2 mb-3">
  <%= link_to attempts_path(kinds: params[:kinds], status: :success, search: params[:search]), class: 'crm-tag crm-tag--success' do %> success <i class="fas fa-check"></i><% end %>
  <%= link_to attempts_path(kinds: params[:kinds], status: :fail, search: params[:search]), class: 'crm-tag crm-tag--danger' do %> fail <i class="fas fa-times"></i><% end %>
  <%= link_to attempts_path(kinds: params[:kinds], status: :error, search: params[:search]), class: 'crm-tag crm-tag--warning' do %> error <i class="fa-solid fa-wrench"></i><% end %>
</div>
```

(`row`/`btn-group`/`role="group"` eram só para o agrupamento visual de botões colados — como viraram chips separados, um simples flex com `gap-2` já resolve o espaçamento; `mb-3`/`justify-content-center`/`d-flex` são utilitários Bootstrap de layout, mantidos sem alteração de comportamento.)

- [ ] **Step 2: `attempts/index.html.erb` — card de pesquisa avançada**

Before (`app/views/attempts/index.html.erb:13-32`):
```erb
<%= form_tag(attempts_path, method: 'get') do %>
  <div class="card mb-lg advanced-search-form bg-dark text-light" id="filters">
    <%= hidden_field_tag :status, {}, value: params[:status] %>
    <%= hidden_field_tag :kinds, {}, value: params[:kinds] %>
    <div class="card-header text-info">
      Pesquisa avançada
    </div>
    <div class="card-body">
      <div class="row">
        <div class="col-sm-12">
          <%= label_tag :search, 'Procurar' %>
          <%= text_field_tag :search, params[:search], class: 'form-control', placeholder: 'Pesquise por número pedido Bling/Nota Fiscal ou por erro' %>
        </div>
      </div>
    </div>
    <div class="card-footer">
      <%= button_tag class: 'btn btn-secondary text-info', name: '' do %><i class="fa fa-search text-info"></i> Pesquisar<% end %>
    </div>
  </div>
<% end %>
```

After:
```erb
<%= form_tag(attempts_path, method: 'get') do %>
  <div class="crm-card advanced-search-form mb-lg" id="filters">
    <%= hidden_field_tag :status, {}, value: params[:status] %>
    <%= hidden_field_tag :kinds, {}, value: params[:kinds] %>
    <div class="fw-bold border-bottom pb-2 mb-3">
      Pesquisa avançada
    </div>
    <div class="row">
      <div class="col-sm-12">
        <%= label_tag :search, 'Procurar', class: 'crm-label' %>
        <%= text_field_tag :search, params[:search], class: 'crm-input', placeholder: 'Pesquise por número pedido Bling/Nota Fiscal ou por erro' %>
      </div>
    </div>
    <div class="border-top pt-3 mt-3">
      <%= button_tag class: 'crm-btn crm-btn--secondary', name: '' do %><i class="fa fa-search"></i> Pesquisar<% end %>
    </div>
  </div>
<% end %>
```

(`id="filters"` e `advanced-search-form` mantidos — não há JS/CSS de outro arquivo que dependa deles hoje, mas preserve por segurança/rastreabilidade. `card-header`/`card-body`/`card-footer` do Bootstrap somem porque `.crm-card` já dá padding uniforme; as divisórias viram `border-bottom`/`border-top` + utilitários de espaçamento do Bootstrap (`pb-2`, `mb-3`, `pt-3`, `mt-3`), que são só layout, não cor.)

- [ ] **Step 3: `attempts/index.html.erb` — tabela e badges**

Before (`app/views/attempts/index.html.erb:34-89`, trechos relevantes):
```erb
    <table class="table table-dark table-hover table-responsive" style="overflow-x: scroll;" id="attemps-table">
```
```erb
              <% if params[:status] == 'success' %>
                <%= link_to reprocess_attempts_path(attempt_id: attempt.id), class: 'btn btn-sm btn-secondary text-info' do %> 
                  <i class="fa-solid fa-repeat"></i>
                <% end %>
              <% end %>
```
```erb
              <span class="badge bg-primary" style="cursor: pointer;" onclick="window.open('<%=ENV.fetch('TINY_SELLS_URL')%>#edit/<%= attempt.tiny_order_id %>', '_blank');">
                Ver no Bling
              </span>
```
```erb
            <td class="text-center"><%= attempt.error.present? ? attempt.error : "<span class='badge bg-secondary'>x</span>".html_safe %></td>
            <td class="text-center"><%= attempt.message.present? ? attempt.message : "<span class='badge bg-secondary'>x</span>".html_safe %></td>
```

After:
```erb
    <table class="crm-table" style="overflow-x: scroll;" id="attemps-table">
```
```erb
              <% if params[:status] == 'success' %>
                <%= link_to reprocess_attempts_path(attempt_id: attempt.id), class: 'crm-btn crm-btn--secondary' do %>
                  <i class="fa-solid fa-repeat"></i>
                <% end %>
              <% end %>
```
```erb
              <span class="crm-tag crm-tag--neutral" style="cursor: pointer;" onclick="window.open('<%=ENV.fetch('TINY_SELLS_URL')%>#edit/<%= attempt.tiny_order_id %>', '_blank');">
                Ver no Bling
              </span>
```
```erb
            <td class="text-center"><%= attempt.error.present? ? attempt.error : "<span class='crm-tag crm-tag--neutral'>x</span>".html_safe %></td>
            <td class="text-center"><%= attempt.message.present? ? attempt.message : "<span class='crm-tag crm-tag--neutral'>x</span>".html_safe %></td>
```

(As duas ocorrências de `badge bg-secondary` recebem exatamente a mesma troca — listadas juntas por serem idênticas. `style="overflow-x: scroll;"` e o `onclick` do "Ver no Bling" não são tocados, são comportamento/layout, não cor.)

- [ ] **Step 4: `attempts/verify_attempts.html.erb` — card, tabela e badges**

Before (`app/views/attempts/verify_attempts.html.erb:3-41`, trechos relevantes):
```erb
<div class="card bg-secondary" style="overflow-x:scroll;">
  <table class="table table-dark table-hover table-responsive" id="attemps-table">
```
```erb
          <td class="text-center" style="min-width:12em;">
            <%= attempt.bling_order_id  %> -
            <span class="badge bg-primary" style="cursor: pointer;" onclick="window.open('<%=ENV.fetch('TINY_SELLS_URL')%>#edit/<%= attempt.bling_order_id  %>', '_blank');">
              Ver no Bling
            </span>
          </td>
```
```erb
            <% if attempt.xml_nota.present? %>
              <button class="btn btn-primary" onclick="copiarConteudo(<%= attempt.id %>)">Copiar XML</button>
            <% end %>
```

After:
```erb
<div class="crm-card" style="overflow-x:scroll;">
  <table class="table crm-table" id="attemps-table">
```
```erb
          <td class="text-center" style="min-width:12em;">
            <%= attempt.bling_order_id  %> -
            <span class="crm-tag crm-tag--neutral" style="cursor: pointer;" onclick="window.open('<%=ENV.fetch('TINY_SELLS_URL')%>#edit/<%= attempt.bling_order_id  %>', '_blank');">
              Ver no Bling
            </span>
          </td>
```
```erb
            <% if attempt.xml_nota.present? %>
              <button class="crm-btn crm-btn--primary" onclick="copiarConteudo(<%= attempt.id %>)">Copiar XML</button>
            <% end %>
```

**Importante:** note que `class="table crm-table"` mantém `table` (não remova) — é o seletor usado por `$('.table').DataTable()` na linha 57 do mesmo arquivo. Todo o restante do `<script>` (linhas 55-82) não é tocado.

- [ ] **Step 5: Verificar visualmente**

Acessar `/crm/attempts` e `/crm/attempts/verify_attempts` (ou rota equivalente de `verify_attempts`) em tema claro e escuro:
- Chips de status (success/fail/error) no topo de `attempts/index` devem navegar corretamente ao clicar (comportamento de link inalterado) e usar as cores de `.crm-tag--success/--danger/--warning`.
- Card "Pesquisa avançada" deve ter fundo/borda do tema (não mais fixo escuro/`bg-dark`) e continuar submetendo a busca normalmente.
- Em `verify_attempts`, confirmar no DevTools que o DataTables inicializou (paginação/busca nativos do DataTables aparecem no rodapé da tabela) — se sumir, é sinal de que a classe `table` foi removida por engano.
- Botão "Copiar XML" deve continuar copiando o conteúdo (clique e confira clipboard/console).
- Badge "Ver no Bling" deve abrir a popup/nova aba com a URL do Bling ao clicar, em ambas as páginas.
- Avaliar se as cores do CSS default do DataTables (`datatables/media/css/jquery.dataTables.min.css`, ainda carregado globalmente) conflitam visualmente com os tokens no tema escuro — é um problema pré-existente fora do escopo desta task, mas vale registrar se ficar muito ruim.

- [ ] **Step 6: Commit**
```bash
git add app/views/attempts/index.html.erb app/views/attempts/verify_attempts.html.erb
git commit -m "style(attempts): migrate attempts views to crm-* components"
```

---

## Área 7 — Devise / Autenticação

## Grupo G: Devise / Autenticação

Escopo: `app/views/devise/**` exceto `app/views/devise/mailer/*` (fora de escopo, são e-mails).

Achado importante antes de detalhar as tasks: as 7 views "pequenas" (`passwords/*`, `registrations/*`,
`confirmations/new`, `unlocks/new`) e os 2 partials `shared/*` são o scaffold padrão do gem Devise, **sem
nenhuma classe Bootstrap** (`btn`, `form-control`, `form-label`, `alert` etc. não aparecem em nenhuma delas —
confirmado via grep). Só usam `class="field"` / `class="actions"` genéricos, sem nenhuma regra CSS associada
em `app/assets/stylesheets/` (também confirmado via grep: `.field`, `.actions` e `#error_explanation` não
têm nenhum seletor correspondente hoje). Ou seja, essas 7 telas hoje renderizam como HTML **totalmente sem
estilo** (fonte do browser, sem cor, sem espaçamento) — não é uma migração de Bootstrap→tokens, é o primeiro
estilo real que essas páginas vão receber. Isso está sinalizado para o usuário no resumo final.

Todas as tasks deste grupo dependem de `app/assets/stylesheets/tokens.scss` e de
`app/assets/stylesheets/components/{_button,_input,_card}.scss` existirem (criados por outra task do plano
maior) e de estarem `@import`ados/`require`ados em `admin.scss` antes de `pages/auth.scss`. Não verifiquei
isso aqui porque essa task ainda não foi aplicada no repo; apenas a ordem relativa (`require pages/auth`
antes de `require_self`, depois dos requires de componentes) é definida abaixo.

---

### Task 47: Tela de login (`devise/sessions/new`) — extrair `<style>` inline para `pages/auth.scss`

Esta tela **já passou por um redesign visual próprio** (layout dividido em dois painéis, paleta índigo
`#3b4adf`, campos com ícone, animação de typewriter). Ela não usa Bootstrap. O trabalho aqui é
majoritariamente *housekeeping* (tirar CSS de dentro do `.html.erb`) e não um retrabalho visual completo —
ver nota de decisão ao final da task.

**Files:**
- Create: `app/assets/stylesheets/pages/auth.scss`
- Modify: `app/views/devise/sessions/new.html.erb:114-474` (remove bloco `<style>`)
- Modify: `app/assets/stylesheets/admin.scss:13-23` (adiciona `*= require pages/auth`)

**Interfaces:**
- Consumes: `--bg` de `app/assets/stylesheets/tokens.scss` (única variável do design system com match exato
  no CSS existente desta tela — ver tabela abaixo).
- Produces: `app/assets/stylesheets/pages/auth.scss` com o seletor raiz `.lp` e todos os `.lp__*`, consumido
  também pelas Tasks G-2/G-3/G-4 (classes utilitárias `.crm-auth-wrap`, `.crm-auth-errors`,
  `.crm-auth-links` adicionadas por essas tasks vivem no mesmo arquivo).

**Tabela de substituição mecânica (valor fixo → token), construída a partir de um grep literal de todas as
cores hex/rgba no bloco `<style>` atual — `#3b4adf` (8×), `#ffffff`/`#fff` (6×), `#f8f9fc` (3×), `#f4f5fd`
(2×), `#e4e7f0` (2×), `#7a83aa` (2×), `#4a5380` (2×), e mais uma dúzia de tons únicos de índigo/slate):**

| Valor fixo encontrado | Token | Observação |
|---|---|---|
| `background: #ffffff;` (em `.lp`, `.lp__panel`, `.lp__card`) | `var(--bg)` | único match exato de cor com a lista de tokens |
| `font-family: -apple-system, BlinkMacSystemFont, 'Inter', 'Segoe UI', sans-serif;` (seletor raiz `.lp`) | *(remover a declaração)* | já vem de `tokens.scss` / regra global de `font-family: 'Google Sans Flex', 'Roboto', ui-sans-serif, sans-serif` |
| Todo o restante (`#3b4adf` e variações `#2d3ccc`/`#2c3bbf`, `#f8f9fc`, `#f4f5fd`, `#e4e7f0`, `#dde1f8`, `#c8ceea`, `#eef0f8`, `#eef0fd`, `#7a83aa`, `#4a5380`, `#3a4170`, `#1b2255`, `#0f1538`, `#a0aac4`, `#aab0cc`, `#b8c0d8`, `#22c55e`, e todos os `rgba(59,74,223,*)`, `rgba(30,40,100,*)`) | **sem token correspondente — permanece como está** | é uma paleta índigo/slate própria da tela, distinta de `--primary` (#1967d2) e `--fg`/`--outline`. Ver nota de decisão. |
| `border-radius` (`8px`, `12px`, `16px`, `20px`, `100px`) | **sem token correspondente — permanece como está** | nenhum desses valores é igual a `--radius` (0.45rem ≈ 7.2px) |

- [ ] **Step 1: Criar `app/assets/stylesheets/pages/auth.scss` com o conteúdo movido**

  Copiar integralmente o conteúdo hoje em `app/views/devise/sessions/new.html.erb:115-473` (de `*, *::before,
  *::after { ... }` até o fechamento do último `@media (max-width: 480px) { ... }`) para o novo arquivo,
  aplicando **apenas** as duas substituições da tabela acima. Exemplo do topo do arquivo resultante:

  ```scss
  // app/assets/stylesheets/pages/auth.scss
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

  .lp {
    display: flex;
    min-height: 100vh;
    background: var(--bg);
  }

  .lp__panel {
    position: relative;
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 3rem 2.5rem;
    background: var(--bg);
    overflow: hidden;
    border-right: 1px solid #eef0f8;
  }
  ```

  E, mais adiante, o `.lp__card`:

  ```scss
  .lp__card {
    position: relative;
    z-index: 1;
    background: var(--bg);
    border: 1px solid #e4e7f0;
    border-radius: 20px;
    padding: 2.25rem 2rem;
    width: 100%;
    max-width: 420px;
    box-shadow: 0 8px 32px rgba(30,40,100,0.09), 0 1px 4px rgba(30,40,100,0.05);
  }
  ```

  Todo o resto (`.lp__dots`, `.lp__line`, `.lp__pill*`, `.lp__tagline`, `.lp__form-side`, `.lp__corner*`,
  `.lp__card-badge`, `.lp__card-title`, `.lp__field*`, `.lp__row`, `.lp__remember*`, `.lp__forgot`,
  `.lp__submit*`, `.lp__secure`, os dois `@media`) é copiado **sem alteração de valores**.

- [ ] **Step 2: Remover o bloco `<style>` de `sessions/new.html.erb`, manter o `<script>`**

  Antes (`app/views/devise/sessions/new.html.erb:112-476`):
  ```erb
  </div>

  <style>
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
  ...
  </style>

  <script>
  document.addEventListener("DOMContentLoaded", function () {
  ```

  Depois:
  ```erb
  </div>

  <script>
  document.addEventListener("DOMContentLoaded", function () {
  ```

  O `<script>` (linhas 476-502, animação de typewriter) fica intocado — é comportamento, não aparência.

- [ ] **Step 3: Registrar `pages/auth.scss` no manifest**

  Em `app/assets/stylesheets/admin.scss`, adicionar o require logo antes de `require_self`:

  Antes (`app/assets/stylesheets/admin.scss:13-23`):
  ```
   *= require bootstrap
   *= require datatables/media/css/jquery.dataTables.min.css
   *= require layouts/global
   *= require layouts/wrapper
   *= require layouts/utils
   *= require layouts/header
   *= require layouts/chosen
   *= require layouts/products
   *= require layouts/orders
   *= require layouts/customers
   *= require_self
  ```

  Depois:
  ```
   *= require bootstrap
   *= require datatables/media/css/jquery.dataTables.min.css
   *= require layouts/global
   *= require layouts/wrapper
   *= require layouts/utils
   *= require layouts/header
   *= require layouts/chosen
   *= require layouts/products
   *= require layouts/orders
   *= require layouts/customers
   *= require pages/auth
   *= require_self
  ```

- [ ] **Step 4: Verificar visualmente `/crm/users/sign_in`**
  - Claro: painel esquerdo (dots/linhas/pill/typewriter) e card de login devem ficar **pixel-idênticos** ao
    estado atual — a única mudança visível esperada é nenhuma, já que `#ffffff` e `var(--bg)` resolvem para
    a mesma cor no tema claro.
  - Escuro (`<html class="theme-dark">`, se já houver toggle implementado por outra task; senão forçar a
    classe manualmente no devtools): `.lp`, `.lp__panel` e `.lp__card` devem escurecer (fundo `var(--bg)`
    dark = `#121317`), mas **todo o resto do texto/bordas/ícones permanece na paleta índigo/slate clara
    original** (`#4a5380`, `#0f1538`, `#e4e7f0` etc. não têm token, não escurecem) — resultado esperado é uma
    tela com fundo escuro e texto/bordas ainda claros, ou seja, **ilegível/quebrada em dark mode**. Isso é
    esperado dado o escopo desta task (só housekeeping mecânico) — não corrigir aqui, ver nota abaixo.
  - Conferir que o efeito typewriter no `#tw-text` ainda funciona (não fizemos alteração de JS).

- [ ] **Step 5: Commit**
  ```bash
  git add app/views/devise/sessions/new.html.erb app/assets/stylesheets/pages/auth.scss app/assets/stylesheets/admin.scss
  git commit -m "Extract sessions/new inline <style> into pages/auth.scss"
  ```

**Nota de decisão para o usuário (não decidido nesta task):** a tela de login usa uma paleta índigo
(`#3b4adf`) inteiramente própria, sem nenhuma correspondência com os tokens do design system
(`--primary` é azul `#1967d2`, não índigo), e não tem tema escuro real — só o fundo escureceria com a
troca mecânica de `#ffffff`→`var(--bg)`, deixando texto/bordas claros sobre fundo escuro. Duas opções pra
uma task futura, fora do escopo mecânico daqui: (a) manter a tela de login com marca própria e **não**
participar do tema escuro (reverter até a troca de `#ffffff`→`var(--bg)` e fixar `background:#fff` fixo), ou
(b) fazer um retrabalho completo repintando toda a paleta índigo/slate para os tokens (`--primary`, `--fg`,
`--fg-alt`, `--outline`) para ganhar suporte real a dark mode. Esta task (G-1) não escolhe nenhuma das duas —
só move o CSS e aplica os dois matches exatos que existem.

---

### Task 48: Partials compartilhados (`devise/shared/_error_messages`, `devise/shared/_links`)

Essas duas partials são renderizadas por todas as views das Tasks G-3 e G-4, então entram primeiro. Nenhuma
tem classe Bootstrap hoje.

**Files:**
- Modify: `app/views/devise/shared/_error_messages.html.erb:1-15`
- Modify: `app/views/devise/shared/_links.html.erb:1-25`
- Modify: `app/assets/stylesheets/pages/auth.scss` (acrescenta `.crm-auth-errors` e `.crm-auth-links`, criado
  na Task 47)

**Interfaces:**
- Consumes: `.crm-btn`, `.crm-btn--secondary` (componentes), `--outline`/`--radius`/`--fg`/`--primary`
  (tokens).
- Produces: classes `.crm-auth-errors` e `.crm-auth-links`, consumidas pelas views das Tasks G-3/G-4.

- [ ] **Step 1: Adicionar wrapper com classe em `_error_messages.html.erb`**

  Antes (`app/views/devise/shared/_error_messages.html.erb:1-15`):
  ```erb
  <% if resource.errors.any? %>
    <div id="error_explanation" data-turbo-cache="false">
      <h2>
        <%= I18n.t("errors.messages.not_saved",
                   count: resource.errors.count,
                   resource: resource.class.model_name.human.downcase)
         %>
      </h2>
      <ul>
        <% resource.errors.full_messages.each do |message| %>
          <li><%= message %></li>
        <% end %>
      </ul>
    </div>
  <% end %>
  ```

  Depois:
  ```erb
  <% if resource.errors.any? %>
    <div id="error_explanation" class="crm-auth-errors" data-turbo-cache="false">
      <h2 class="crm-auth-errors__title">
        <%= I18n.t("errors.messages.not_saved",
                   count: resource.errors.count,
                   resource: resource.class.model_name.human.downcase)
         %>
      </h2>
      <ul>
        <% resource.errors.full_messages.each do |message| %>
          <li><%= message %></li>
        <% end %>
      </ul>
    </div>
  <% end %>
  ```

  Nota: não existe token de cor de erro/perigo na lista fornecida (`tokens.scss` só define
  `--primary`/`--bg`/`--fg`/`--fg-alt`/`--chrome-*`/`--outline`/`--primary-tint`/`--radius`). Sinalizado no
  resumo final — `.crm-auth-errors` abaixo usa só tokens neutros (`--outline`, `--fg`), sem cor semântica de
  erro.

- [ ] **Step 2: Adicionar wrapper com classe em `_links.html.erb`**

  Antes (`app/views/devise/shared/_links.html.erb:1-25`, trecho):
  ```erb
  <%- if controller_name != 'sessions' %>
    <%= link_to "Log in", new_session_path(resource_name) %><br />
  <% end %>

  <%- if devise_mapping.registerable? && controller_name != 'registrations' %>
    <%= link_to "Sign up", new_registration_path(resource_name) %><br />
  <% end %>
  ```

  Depois (envolve tudo num wrapper e remove os `<br />`, já que `.crm-auth-links` usa `flex-direction:
  column` com `gap`; mesmo padrão aplicado às 3 condicionais seguintes e ao bloco omniauth):
  ```erb
  <div class="crm-auth-links">
    <%- if controller_name != 'sessions' %>
      <%= link_to "Log in", new_session_path(resource_name) %>
    <% end %>

    <%- if devise_mapping.registerable? && controller_name != 'registrations' %>
      <%= link_to "Sign up", new_registration_path(resource_name) %>
    <% end %>

    <%- if devise_mapping.recoverable? && controller_name != 'passwords' && controller_name != 'registrations' %>
      <%= link_to "Forgot your password?", new_password_path(resource_name) %>
    <% end %>

    <%- if devise_mapping.confirmable? && controller_name != 'confirmations' %>
      <%= link_to "Didn't receive confirmation instructions?", new_confirmation_path(resource_name) %>
    <% end %>

    <%- if devise_mapping.lockable? && resource_class.unlock_strategy_enabled?(:email) && controller_name != 'unlocks' %>
      <%= link_to "Didn't receive unlock instructions?", new_unlock_path(resource_name) %>
    <% end %>

    <%- if devise_mapping.omniauthable? %>
      <%- resource_class.omniauth_providers.each do |provider| %>
        <%= button_to "Sign in with #{OmniAuth::Utils.camelize(provider)}", omniauth_authorize_path(resource_name, provider), class: 'crm-btn crm-btn--secondary', data: { turbo: false } %>
      <% end %>
    <% end %>
  </div>
  ```

- [ ] **Step 3: Adicionar as classes de página em `app/assets/stylesheets/pages/auth.scss`**

  Acrescentar ao final do arquivo criado na Task 47:
  ```scss
  // Views devise pequenas (passwords/registrations/confirmations/unlocks) — Tasks G-2/G-3/G-4
  .crm-auth-wrap {
    max-width: 420px;
    margin: 3rem auto;
  }

  .crm-auth-errors {
    border: 1px solid var(--outline);
    border-radius: var(--radius);
    padding: .75rem 1rem;
    margin-bottom: 1rem;
    color: var(--fg);
  }

  .crm-auth-errors__title {
    font-size: .9rem;
    font-weight: 700;
    margin-bottom: .35rem;
  }

  .crm-auth-links {
    display: flex;
    flex-direction: column;
    gap: .5rem;
    margin-top: 1rem;
    font-size: .8125rem;
    text-align: center;
  }

  .crm-auth-links a {
    color: var(--primary);
    text-decoration: none;
  }

  .crm-auth-links a:hover {
    text-decoration: underline;
  }
  ```

- [ ] **Step 4: Verificar visualmente**
  - Provocar um erro de validação (ex.: submeter `/crm/users/password/new` com e-mail inválido, ou
    `/crm/users/sign_up` — se registro estiver habilitado — com senhas divergentes) e conferir que a caixa
    de erro aparece com borda `var(--outline)` e texto legível em claro e escuro.
  - Em qualquer tela pequena (ex. `/crm/users/password/new`), conferir que os links no rodapé ficam
    empilhados verticalmente, com espaçamento uniforme, cor `var(--primary)` e sublinhado só no hover — em
    claro e escuro.

- [ ] **Step 5: Commit**
  ```bash
  git add app/views/devise/shared/_error_messages.html.erb app/views/devise/shared/_links.html.erb app/assets/stylesheets/pages/auth.scss
  git commit -m "Style devise shared error/links partials with crm-auth-* classes"
  ```

---

### Task 49: Formulários simples de um campo (`passwords/new`, `passwords/edit`, `confirmations/new`, `unlocks/new`)

As quatro views têm exatamente a mesma estrutura: `<h2>` de título, um `form_for` com 1-2 campos dentro de
`div.field`, um `div.actions` com `f.submit`, e `render "devise/shared/links"`. Tratadas numa task só, um
step por arquivo.

**Files:**
- Modify: `app/views/devise/passwords/new.html.erb:1-16`
- Modify: `app/views/devise/passwords/edit.html.erb:1-25`
- Modify: `app/views/devise/confirmations/new.html.erb:1-16`
- Modify: `app/views/devise/unlocks/new.html.erb:1-16`

**Interfaces:**
- Consumes: `.crm-card`, `.crm-auth-wrap` (Task 48), `.crm-label`, `.crm-input`, `.crm-btn`,
  `.crm-btn--primary`.
- Produces: nenhuma nova classe — só consome as das Tasks G-1/G-2.

- [ ] **Step 1: `passwords/new.html.erb`**

  Antes (arquivo inteiro, 16 linhas):
  ```erb
  <h2>Forgot your password?</h2>

  <%= form_for(resource, as: resource_name, url: password_path(resource_name), html: { method: :post }) do |f| %>
    <%= render "devise/shared/error_messages", resource: resource %>

    <div class="field">
      <%= f.label :email %><br />
      <%= f.email_field :email, autofocus: true, autocomplete: "email" %>
    </div>

    <div class="actions">
      <%= f.submit "Send me reset password instructions" %>
    </div>
  <% end %>

  <%= render "devise/shared/links" %>
  ```

  Depois:
  ```erb
  <div class="crm-auth-wrap crm-card">
    <h2>Forgot your password?</h2>

    <%= form_for(resource, as: resource_name, url: password_path(resource_name), html: { method: :post }) do |f| %>
      <%= render "devise/shared/error_messages", resource: resource %>

      <div class="field">
        <%= f.label :email, class: 'crm-label' %>
        <%= f.email_field :email, autofocus: true, autocomplete: "email", class: 'crm-input' %>
      </div>

      <div class="actions">
        <%= f.submit "Send me reset password instructions", class: 'crm-btn crm-btn--primary' %>
      </div>
    <% end %>

    <%= render "devise/shared/links" %>
  </div>
  ```

- [ ] **Step 2: `passwords/edit.html.erb`**

  Antes (arquivo inteiro, 25 linhas):
  ```erb
  <h2>Change your password</h2>

  <%= form_for(resource, as: resource_name, url: password_path(resource_name), html: { method: :put }) do |f| %>
    <%= render "devise/shared/error_messages", resource: resource %>
    <%= f.hidden_field :reset_password_token %>

    <div class="field">
      <%= f.label :password, "New password" %><br />
      <% if @minimum_password_length %>
        <em>(<%= @minimum_password_length %> characters minimum)</em><br />
      <% end %>
      <%= f.password_field :password, autofocus: true, autocomplete: "new-password" %>
    </div>

    <div class="field">
      <%= f.label :password_confirmation, "Confirm new password" %><br />
      <%= f.password_field :password_confirmation, autocomplete: "new-password" %>
    </div>

    <div class="actions">
      <%= f.submit "Change my password" %>
    </div>
  <% end %>

  <%= render "devise/shared/links" %>
  ```

  Depois:
  ```erb
  <div class="crm-auth-wrap crm-card">
    <h2>Change your password</h2>

    <%= form_for(resource, as: resource_name, url: password_path(resource_name), html: { method: :put }) do |f| %>
      <%= render "devise/shared/error_messages", resource: resource %>
      <%= f.hidden_field :reset_password_token %>

      <div class="field">
        <%= f.label :password, "New password", class: 'crm-label' %>
        <% if @minimum_password_length %>
          <em>(<%= @minimum_password_length %> characters minimum)</em>
        <% end %>
        <%= f.password_field :password, autofocus: true, autocomplete: "new-password", class: 'crm-input' %>
      </div>

      <div class="field">
        <%= f.label :password_confirmation, "Confirm new password", class: 'crm-label' %>
        <%= f.password_field :password_confirmation, autocomplete: "new-password", class: 'crm-input' %>
      </div>

      <div class="actions">
        <%= f.submit "Change my password", class: 'crm-btn crm-btn--primary' %>
      </div>
    <% end %>

    <%= render "devise/shared/links" %>
  </div>
  ```

- [ ] **Step 3: `confirmations/new.html.erb`**

  Antes (arquivo inteiro, 16 linhas):
  ```erb
  <h2>Resend confirmation instructions</h2>

  <%= form_for(resource, as: resource_name, url: confirmation_path(resource_name), html: { method: :post }) do |f| %>
    <%= render "devise/shared/error_messages", resource: resource %>

    <div class="field">
      <%= f.label :email %><br />
      <%= f.email_field :email, autofocus: true, autocomplete: "email", value: (resource.pending_reconfirmation? ? resource.unconfirmed_email : resource.email) %>
    </div>

    <div class="actions">
      <%= f.submit "Resend confirmation instructions" %>
    </div>
  <% end %>

  <%= render "devise/shared/links" %>
  ```

  Depois:
  ```erb
  <div class="crm-auth-wrap crm-card">
    <h2>Resend confirmation instructions</h2>

    <%= form_for(resource, as: resource_name, url: confirmation_path(resource_name), html: { method: :post }) do |f| %>
      <%= render "devise/shared/error_messages", resource: resource %>

      <div class="field">
        <%= f.label :email, class: 'crm-label' %>
        <%= f.email_field :email, autofocus: true, autocomplete: "email", value: (resource.pending_reconfirmation? ? resource.unconfirmed_email : resource.email), class: 'crm-input' %>
      </div>

      <div class="actions">
        <%= f.submit "Resend confirmation instructions", class: 'crm-btn crm-btn--primary' %>
      </div>
    <% end %>

    <%= render "devise/shared/links" %>
  </div>
  ```

- [ ] **Step 4: `unlocks/new.html.erb`**

  Antes (arquivo inteiro, 16 linhas):
  ```erb
  <h2>Resend unlock instructions</h2>

  <%= form_for(resource, as: resource_name, url: unlock_path(resource_name), html: { method: :post }) do |f| %>
    <%= render "devise/shared/error_messages", resource: resource %>

    <div class="field">
      <%= f.label :email %><br />
      <%= f.email_field :email, autofocus: true, autocomplete: "email" %>
    </div>

    <div class="actions">
      <%= f.submit "Resend unlock instructions" %>
    </div>
  <% end %>

  <%= render "devise/shared/links" %>
  ```

  Depois:
  ```erb
  <div class="crm-auth-wrap crm-card">
    <h2>Resend unlock instructions</h2>

    <%= form_for(resource, as: resource_name, url: unlock_path(resource_name), html: { method: :post }) do |f| %>
      <%= render "devise/shared/error_messages", resource: resource %>

      <div class="field">
        <%= f.label :email, class: 'crm-label' %>
        <%= f.email_field :email, autofocus: true, autocomplete: "email", class: 'crm-input' %>
      </div>

      <div class="actions">
        <%= f.submit "Resend unlock instructions", class: 'crm-btn crm-btn--primary' %>
      </div>
    <% end %>

    <%= render "devise/shared/links" %>
  </div>
  ```

- [ ] **Step 5: Verificar visualmente as 4 páginas**
  - `/crm/users/password/new`, `/crm/users/password/edit?reset_password_token=...` (precisa de token válido
    — ou testar só o layout submetendo o form vazio e olhando a tela com erro), `/crm/users/confirmation/new`,
    `/crm/users/unlock/new`.
  - Em cada uma: card branco/cinza-escuro centralizado (`--bg`, borda `--outline`), label em
    `--fg-alt` acima do campo, input com borda `--outline` que vira `--primary` + halo `--primary-tint` no
    focus, botão primário cheio `--primary`. Testar claro e escuro (toggle de tema, se já existir; senão
    forçar `class="theme-dark"` na tag `<html>` via devtools).
  - Testar tab-order e submit com Enter em cada form (nenhum comportamento deve ter mudado, só classes CSS
    foram adicionadas).

- [ ] **Step 6: Commit**
  ```bash
  git add app/views/devise/passwords/new.html.erb app/views/devise/passwords/edit.html.erb app/views/devise/confirmations/new.html.erb app/views/devise/unlocks/new.html.erb
  git commit -m "Apply crm-* design system classes to simple devise forms"
  ```

---

### Task 50: Formulários de registro (`registrations/new`, `registrations/edit`)

Separados da Task 49 porque têm campos extras (confirmação de senha, senha atual) e, no `edit`, uma seção
extra de cancelamento de conta (`button_to` + `link_to "Back"`) fora do form principal.

**Files:**
- Modify: `app/views/devise/registrations/new.html.erb:1-29`
- Modify: `app/views/devise/registrations/edit.html.erb:1-43`

**Interfaces:**
- Consumes: `.crm-card`, `.crm-auth-wrap`, `.crm-auth-links` (Task 48), `.crm-label`, `.crm-input`,
  `.crm-btn`, `.crm-btn--primary`, `.crm-btn--secondary`.
- Produces: nenhuma nova classe.

**Nota:** verificar antes de aplicar — hoje `config/routes.rb` tem `devise_for :user, skip: [:registrations]`,
então essas duas telas podem estar desabilitadas/inacessíveis na rota atual. Migrar de qualquer forma (o
código erb existe e pode voltar a ser usado), mas o Step de verificação visual desta task pode precisar ser
pulado ou feito habilitando `registrations` temporariamente — sinalizar isso no resumo.

- [ ] **Step 1: `registrations/new.html.erb`**

  Antes (arquivo inteiro, 29 linhas):
  ```erb
  <h2>Sign up</h2>

  <%= form_for(resource, as: resource_name, url: registration_path(resource_name)) do |f| %>
    <%= render "devise/shared/error_messages", resource: resource %>

    <div class="field">
      <%= f.label :email %><br />
      <%= f.email_field :email, autofocus: true, autocomplete: "email" %>
    </div>

    <div class="field">
      <%= f.label :password %>
      <% if @minimum_password_length %>
      <em>(<%= @minimum_password_length %> characters minimum)</em>
      <% end %><br />
      <%= f.password_field :password, autocomplete: "new-password" %>
    </div>

    <div class="field">
      <%= f.label :password_confirmation %><br />
      <%= f.password_field :password_confirmation, autocomplete: "new-password" %>
    </div>

    <div class="actions">
      <%= f.submit "Sign up" %>
    </div>
  <% end %>

  <%= render "devise/shared/links" %>
  ```

  Depois:
  ```erb
  <div class="crm-auth-wrap crm-card">
    <h2>Sign up</h2>

    <%= form_for(resource, as: resource_name, url: registration_path(resource_name)) do |f| %>
      <%= render "devise/shared/error_messages", resource: resource %>

      <div class="field">
        <%= f.label :email, class: 'crm-label' %>
        <%= f.email_field :email, autofocus: true, autocomplete: "email", class: 'crm-input' %>
      </div>

      <div class="field">
        <%= f.label :password, class: 'crm-label' %>
        <% if @minimum_password_length %>
        <em>(<%= @minimum_password_length %> characters minimum)</em>
        <% end %>
        <%= f.password_field :password, autocomplete: "new-password", class: 'crm-input' %>
      </div>

      <div class="field">
        <%= f.label :password_confirmation, class: 'crm-label' %>
        <%= f.password_field :password_confirmation, autocomplete: "new-password", class: 'crm-input' %>
      </div>

      <div class="actions">
        <%= f.submit "Sign up", class: 'crm-btn crm-btn--primary' %>
      </div>
    <% end %>

    <%= render "devise/shared/links" %>
  </div>
  ```

- [ ] **Step 2: `registrations/edit.html.erb`**

  Antes (arquivo inteiro, 43 linhas):
  ```erb
  <h2>Edit <%= resource_name.to_s.humanize %></h2>

  <%= form_for(resource, as: resource_name, url: registration_path(resource_name), html: { method: :put }) do |f| %>
    <%= render "devise/shared/error_messages", resource: resource %>

    <div class="field">
      <%= f.label :email %><br />
      <%= f.email_field :email, autofocus: true, autocomplete: "email" %>
    </div>

    <% if devise_mapping.confirmable? && resource.pending_reconfirmation? %>
      <div>Currently waiting confirmation for: <%= resource.unconfirmed_email %></div>
    <% end %>

    <div class="field">
      <%= f.label :password %> <i>(leave blank if you don't want to change it)</i><br />
      <%= f.password_field :password, autocomplete: "new-password" %>
      <% if @minimum_password_length %>
        <br />
        <em><%= @minimum_password_length %> characters minimum</em>
      <% end %>
    </div>

    <div class="field">
      <%= f.label :password_confirmation %><br />
      <%= f.password_field :password_confirmation, autocomplete: "new-password" %>
    </div>

    <div class="field">
      <%= f.label :current_password %> <i>(we need your current password to confirm your changes)</i><br />
      <%= f.password_field :current_password, autocomplete: "current-password" %>
    </div>

    <div class="actions">
      <%= f.submit "Update" %>
    </div>
  <% end %>

  <h3>Cancel my account</h3>

  <div>Unhappy? <%= button_to "Cancel my account", registration_path(resource_name), data: { confirm: "Are you sure?", turbo_confirm: "Are you sure?" }, method: :delete %></div>

  <%= link_to "Back", :back %>
  ```

  Depois:
  ```erb
  <div class="crm-auth-wrap crm-card">
    <h2>Edit <%= resource_name.to_s.humanize %></h2>

    <%= form_for(resource, as: resource_name, url: registration_path(resource_name), html: { method: :put }) do |f| %>
      <%= render "devise/shared/error_messages", resource: resource %>

      <div class="field">
        <%= f.label :email, class: 'crm-label' %>
        <%= f.email_field :email, autofocus: true, autocomplete: "email", class: 'crm-input' %>
      </div>

      <% if devise_mapping.confirmable? && resource.pending_reconfirmation? %>
        <div>Currently waiting confirmation for: <%= resource.unconfirmed_email %></div>
      <% end %>

      <div class="field">
        <%= f.label :password, class: 'crm-label' %> <i>(leave blank if you don't want to change it)</i>
        <%= f.password_field :password, autocomplete: "new-password", class: 'crm-input' %>
        <% if @minimum_password_length %>
          <em><%= @minimum_password_length %> characters minimum</em>
        <% end %>
      </div>

      <div class="field">
        <%= f.label :password_confirmation, class: 'crm-label' %>
        <%= f.password_field :password_confirmation, autocomplete: "new-password", class: 'crm-input' %>
      </div>

      <div class="field">
        <%= f.label :current_password, class: 'crm-label' %> <i>(we need your current password to confirm your changes)</i>
        <%= f.password_field :current_password, autocomplete: "current-password", class: 'crm-input' %>
      </div>

      <div class="actions">
        <%= f.submit "Update", class: 'crm-btn crm-btn--primary' %>
      </div>
    <% end %>

    <h3>Cancel my account</h3>

    <div class="crm-auth-links">
      Unhappy? <%= button_to "Cancel my account", registration_path(resource_name), class: 'crm-btn crm-btn--secondary', data: { confirm: "Are you sure?", turbo_confirm: "Are you sure?" }, method: :delete %>
      <%= link_to "Back", :back %>
    </div>
  </div>
  ```

- [ ] **Step 3: Verificar visualmente**
  - Se `registrations` continuar `skip`ado nas rotas (`config/routes.rb:11`), habilitar temporariamente em
    um ambiente local (`devise_for :user` sem o `skip:`) só para visualizar `/crm/users/sign_up` e
    `/crm/users/edit`, depois reverter — **não commitar** essa alteração de rota, ela é escopo de outra
    task/decisão do produto.
  - Conferir alinhamento dos múltiplos campos de senha, texto explicativo em `<i>`/`<em>` legível (herda cor
    do texto do card), botão secundário "Cancel my account" com aparência de outline (não deve parecer
    destrutivo/vermelho — não há token de perigo definido, sinalizado no resumo).
  - Claro e escuro.

- [ ] **Step 4: Commit**
  ```bash
  git add app/views/devise/registrations/new.html.erb app/views/devise/registrations/edit.html.erb
  git commit -m "Apply crm-* design system classes to devise registration forms"
  ```

---

### Task 51: Verificação final completa (rotas + design system + todas as views migradas)

**Files:** nenhum arquivo novo — task de verificação.

**Interfaces:**
- Consumes: todas as tasks anteriores (1-50).
- Produces: confirmação de que rotas, design system e a migração visual completa de todas as views estão corretas e consistentes antes de considerar o plano concluído.

- [ ] **Step 1: Rodar a suíte completa de testes**

Run: `bin/rails test`
Expected: `41 runs, ..., 0 failures, 0 errors` — mesmo total de testes do baseline antes de qualquer mudança deste plano (nenhuma mudança de comportamento, só rota/CSS).

- [ ] **Step 2: Checklist manual no navegador — claro**

- [ ] `/` deslogado: página institucional carrega, botão "Entrar" funciona.
- [ ] `/crm/users/sign_in`: login funciona, redireciona para `/crm` após autenticar.
- [ ] `/crm`: topbar escura, sidebar clara à esquerda com os itens certos por perfil (admin vê tudo, afiliado só "Meus Eventos"), footer no final.
- [ ] `/crm/vendas`: KPIs de ROAS/CAC com `.crm-kpi-card`, cores/tipografia batendo com os tokens.
- [ ] `/crm/orders`, `/crm/products`, `/crm/customers`: tabelas usando `.crm-table`, botões/inputs com `.crm-btn`/`.crm-input`, sem erro 404/500.
- [ ] `/crm/clients` (índice + novo/editar): tabela e formulário migrados, sem CSS `<style>` inline restante.
- [ ] `/crm/campaigns` (índice/show/form): badges de status com `.crm-tag`, formulário com `.crm-input`/`.crm-label`.
- [ ] `/crm/affiliates` (índice/show/form): mesma checagem de campanhas.
- [ ] `/crm/users`, `/crm/profiles` (admin): tabelas/formulários migrados.
- [ ] `/crm/attempts` e `/crm/attempts/verify_attempts`: tabelas com `.crm-table`/`.crm-tag`, DataTables ainda funcional em `verify_attempts`.
- [ ] `/crm/try_on`: página migrada, sem `<style>` inline, funcionalidade de try-on intacta.
- [ ] `/crm/events` (Eventos): KPIs, filtros, tabela de sessões e modal de detalhes usando `.crm-*`, badges de jornada com cores corretas.
- [ ] `/crm/sidekiq` acessível pelo link do dropdown/sidebar (admin).
- [ ] Fluxo Devise completo: `/crm/users/sign_in` (login), "esqueci minha senha", editar senha, confirmação de conta, desbloqueio de conta — todos com o novo visual (`.crm-input`/`.crm-label`/`.crm-btn`), sem erro 404/500 nas rotas ativas.

- [ ] **Step 3: Checklist manual no navegador — escuro**

- [ ] Clicar no botão de tema na topbar: ícone alterna sol/lua, topbar/sidebar/footer trocam de cor.
- [ ] Recarregar a página: tema escolhido persiste.
- [ ] Voltar para `/`: tema escuro escolhido no `/crm` também se reflete lá (mesma classe global em `<html>`).

- [ ] **Step 4: Checklist manual — mobile (< 768px, usar DevTools)**

- [ ] `/crm`: hamburger aparece na topbar, sidebar vira drawer, overlay escurece o fundo, fecha ao clicar fora.
- [ ] `/`: hero e cards empilham em coluna única.
- [ ] Amostragem de 3-4 páginas migradas (ex.: `/crm/orders`, `/crm/campaigns`, tela de login): sem overflow horizontal, tabelas/formulários legíveis em largura de celular.

- [ ] **Step 5: Confirmar ausência de referências antigas**

Run: `grep -rn "painel" config/routes.rb app/controllers/ app/views/ | grep -v "mewtda_painel\|mewtda-painel"`
Expected: nenhum resultado (as ocorrências em `config/cable.yml`/`config/database.yml`/`config/environments/production.rb` são nomes de banco/canal, não rotas — fora de escopo, não tocar).

Este é o checkpoint final do plano: se tudo acima passar, rotas + design system + migração visual completa estão prontos.

---

---

### Task 52: Confirmar independência de outras referências de infraestrutura a "painel" (fora de escopo, só documentar)

**Files:** nenhuma modificação — task de documentação/registro.

**Interfaces:** nenhuma.

- [ ] **Step 1: Registrar explicitamente o que NÃO foi tocado e por quê**

As seguintes ocorrências de "painel" continuam no código de propósito, por não serem rotas HTTP nem visíveis ao usuário final — mudar exigiria migração de dados/infra (nome de banco, prefixo de fila) fora do escopo deste plano:

- `config/database.yml:13` — `database: mewtda_painel_test` (nome do banco de teste).
- `config/cable.yml:11` — `channel_prefix: mewtda_painel_production` (prefixo de canal do Action Cable em produção).
- `config/environments/production.rb:63` — comentário `# config.active_job.queue_name_prefix = "mewtda_painel_production"` (linha comentada, sem efeito).

- [ ] **Step 2: Nenhum commit necessário** (task apenas confirma escopo, nada muda no código).

---
