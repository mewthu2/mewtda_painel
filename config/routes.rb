require 'sidekiq/web'

Rails.application.routes.draw do
  root to: redirect('/painel')

  namespace :integrations do
    post '/shopify/events', to: 'shopify_events#create'
  end

  scope '/painel' do
    devise_for :user, skip: [:registrations]

    authenticate :user do
      mount Sidekiq::Web => '/sidekiq'
    end

    get '/', to: 'dashboard#index', as: :painel

    get '/shopify/auth', to: 'shopify_auth#auth'
    get '/shopify/callback', to: 'shopify_auth#callback'

    resources :dashboard, only: [:index]

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