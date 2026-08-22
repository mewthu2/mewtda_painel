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

    get   'automacoes',          to: 'automations#index',         as: :automations
    get   'automacoes/rastreio', to: 'automations#edit_tracking', as: :edit_tracking_automation
    patch 'automacoes/rastreio', to: 'automations#update_tracking', as: :tracking_automation

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

    get 'clients/:id/shopify/auth', to: 'shopify_auth#auth', as: :client_shopify_auth
    get '/shopify/callback', to: 'shopify_auth#callback'

    get    'clients/:id/google_ads/connect', to: 'google_ads#connect', as: :client_google_ads_connect
    get    'google_ads/callback', to: 'google_ads#callback', as: :google_ads_callback
    delete 'clients/:id/google_ads/disconnect', to: 'google_ads#disconnect', as: :client_google_ads_disconnect

    resources :dashboard, only: [:index]

    get  'vendas',               to: 'sales_dashboard#index', as: :sales_dashboard
    get  'vendas/export_xlsx',   to: 'sales_dashboard#export_xlsx',   as: :export_xlsx_sales_dashboard
    post 'vendas/sync_ad_costs', to: 'sales_dashboard#sync_ad_costs', as: :sync_ad_costs_sales_dashboard
    post 'vendas/process_now',   to: 'sales_dashboard#process_now',   as: :process_now_sales_dashboard
    get  'vendas/orders_for_day', to: 'sales_dashboard#orders_for_day', as: :orders_for_day_sales_dashboard

    resources :ad_costs, except: [:show]
    resource :goal, only: %i[edit update]

    resource :settings, path: 'configuracoes', controller: 'settings', only: [:edit, :update]
    resource :account, path: 'minha-conta', controller: 'account', only: [:edit, :update]

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

    resources :users do
      member do
        patch :reset_password
      end
    end
    resources :profiles

    resources :attempts, only: [:index] do
      collection do
        get :verify_attempts
      end
    end
  end
end
