# Rename /painel → /crm + Nova Página Institucional + Fundação do Redesign Visual — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mover o app hoje em `/painel` para `/crm`, liberar `/` para uma página institucional pública, e construir a fundação do redesign visual (tokens de cor, dark mode, componentes base, topbar + sidebar, footer) definida no spec `docs/superpowers/specs/2026-08-09-visual-redesign-design.md`.

**Architecture:** Rails 7 (Sprockets/SCSS, importmap, Devise, Turbo). Rotas: `root` passa de `redirect('/painel')` para `home#index` (público); o `scope '/painel'` vira `scope '/crm'` com a rota nomeada `:painel` renomeada para `:crm`. CSS: substitui blocos `<style>` inline por SCSS organizado em `app/assets/stylesheets/{tokens,layouts/*,components/*,pages/*}.scss`, usando CSS custom properties para permitir dark mode via classe `.theme-dark` em `<html>`, sem coluna nova no banco (persistido em `localStorage`).

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
- **Fora de escopo deste plano:** a migração visual (remoção de `<style>` inline, adoção das novas classes de componente) das ~24 views autenticadas existentes que já têm estilo inline hoje (`clients/*`, `customers/index`, `orders/index`, `products/index`, `campaigns/*`, `affiliates/*`, `profiles/*`, `users/*`, `events/index`, `attempts/*`, `try_on/index`, `dashboard/index`, `sales_dashboard/index`, `devise/*` exceto a tela de login que já foi redesenhada). Motivo: mapeamento de arquivos nesta etapa de planejamento mostrou que essas 24 views somam mais de 8.000 linhas de ERB/CSS inline específico de cada tela — escrever diffs reais e verificados para cada uma exige ler o conteúdo atual de cada arquivo, o que excede o escopo responsável de um único documento de plano. A Task 15 deste plano entrega um levantamento arquivo-a-arquivo que vira a base de um plano de execução separado, gerado depois que a fundação abaixo estiver no ar e revisada no navegador (mesmo padrão de verificação que o spec já define: cada página é conferida manualmente, claro e escuro).

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
- Produces: classes `.crm-btn`/`.crm-btn--primary`/`.crm-btn--secondary`, `.crm-input`/`.crm-label`, `.crm-table`, `.crm-card`/`.crm-kpi-card`/`.crm-kpi-card__label`/`.crm-kpi-card__value`, `.crm-tag`/`.crm-tag--success`/`.crm-tag--danger`/`.crm-tag--warning`/`.crm-tag--neutral` — usadas pela Task 13 (página institucional) e por qualquer migração de view futura (Task 16).

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

### Task 13: Verificação final da fundação (rotas + design system + navegação + institucional)

**Files:** nenhum arquivo novo — task de verificação.

**Interfaces:**
- Consumes: todas as tasks anteriores (1-12).
- Produces: confirmação de que a fundação está pronta para servir de base à Task 15 (levantamento da migração visual das views restantes).

- [ ] **Step 1: Rodar a suíte completa de testes**

Run: `bin/rails test`
Expected: `41 runs, ..., 0 failures, 0 errors` — mesmo total de testes do baseline antes de qualquer mudança deste plano (nenhuma mudança de comportamento, só rota/CSS).

- [ ] **Step 2: Checklist manual no navegador — claro**

- [ ] `/` deslogado: página institucional carrega, botão "Entrar" funciona.
- [ ] `/crm/users/sign_in`: login funciona, redireciona para `/crm` após autenticar.
- [ ] `/crm`: topbar escura, sidebar clara à esquerda com os itens certos por perfil (admin vê tudo, afiliado só "Meus Eventos"), footer no final.
- [ ] Navegar para `/crm/orders`, `/crm/clients`, `/crm/products`, `/crm/campaigns`, `/crm/affiliates`, `/crm/users` (admin), `/crm/vendas`: todas carregam sem erro 404/500 (ainda com aparência antiga nessas páginas — esperado, é fora de escopo deste plano).
- [ ] `/crm/sidekiq` acessível pelo link do dropdown/sidebar (admin).

- [ ] **Step 3: Checklist manual no navegador — escuro**

- [ ] Clicar no botão de tema na topbar: ícone alterna sol/lua, topbar/sidebar/footer trocam de cor.
- [ ] Recarregar a página: tema escolhido persiste.
- [ ] Voltar para `/`: tema escuro escolhido no `/crm` também se reflete lá (mesma classe global em `<html>`).

- [ ] **Step 4: Checklist manual — mobile (< 768px, usar DevTools)**

- [ ] `/crm`: hamburger aparece na topbar, sidebar vira drawer, overlay escurece o fundo, fecha ao clicar fora.
- [ ] `/`: hero e cards empilham em coluna única.

- [ ] **Step 5: Confirmar ausência de referências antigas**

Run: `grep -rn "painel" config/routes.rb app/controllers/ app/views/ | grep -v "mewtda_painel\|mewtda-painel"`
Expected: nenhum resultado (as ocorrências em `config/cable.yml`/`config/database.yml`/`config/environments/production.rb` são nomes de banco/canal, não rotas — fora de escopo, não tocar).

Este é o ponto de checkpoint antes de decidir seguir para a Task 15 (levantamento da migração visual restante) ou pausar aqui.

---

### Task 14: Confirmar independência de outras referências de infraestrutura a "painel" (fora de escopo, só documentar)

**Files:** nenhuma modificação — task de documentação/registro.

**Interfaces:** nenhuma.

- [ ] **Step 1: Registrar explicitamente o que NÃO foi tocado e por quê**

As seguintes ocorrências de "painel" continuam no código de propósito, por não serem rotas HTTP nem visíveis ao usuário final — mudar exigiria migração de dados/infra (nome de banco, prefixo de fila) fora do escopo deste plano:

- `config/database.yml:13` — `database: mewtda_painel_test` (nome do banco de teste).
- `config/cable.yml:11` — `channel_prefix: mewtda_painel_production` (prefixo de canal do Action Cable em produção).
- `config/environments/production.rb:63` — comentário `# config.active_job.queue_name_prefix = "mewtda_painel_production"` (linha comentada, sem efeito).

- [ ] **Step 2: Nenhum commit necessário** (task apenas confirma escopo, nada muda no código).

---

### Task 15: Levantamento para o plano de migração visual das 24 views autenticadas restantes

**Files:**
- Create: `docs/superpowers/plans/TODO-crm-views-visual-migration-inventory.md`

**Interfaces:**
- Consumes: componentes base (`.crm-btn`, `.crm-input`, `.crm-label`, `.crm-table`, `.crm-card`, `.crm-kpi-card*`, `.crm-tag*`) da Task 8, tokens da Task 6.
- Produces: documento de levantamento (arquivo/linha de cada bloco `<style>` inline, tamanho, classes usadas hoje) que serve de insumo para escrever, depois, um novo plano (`superpowers:writing-plans`) dedicado só à migração visual — cada página conferida manualmente no navegador, como já define a seção "Verificação" do spec.

- [ ] **Step 1: Gerar a lista de arquivos com `<style>` inline e seu tamanho**

Run: `grep -rl "<style" app/views/ | grep -v "layouts/mailer\|devise/mailer" | xargs wc -l | sort -n`

- [ ] **Step 2: Para cada arquivo da lista, anotar no documento: caminho, nº de linhas do `<style>` (localizar com `grep -n "<style\|</style>"`), classes CSS custom já usadas (prefixo mais comum), e se a página usa DataTables/Chosen/Bootstrap modal (para saber se algo de JS depende do CSS atual antes de remover)**

```bash
for f in $(grep -rl "<style" app/views/ | grep -v "layouts/mailer\|devise/mailer"); do
  echo "== $f ==";
  grep -n "<style\|</style>" "$f";
done
```

Escrever o resultado, organizado por arquivo, em `docs/superpowers/plans/TODO-crm-views-visual-migration-inventory.md`.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/plans/TODO-crm-views-visual-migration-inventory.md
git commit -m "docs: inventory remaining views for a follow-up visual migration plan"
```
