require 'sidekiq/web'

Rails.application.routes.draw do
  devise_for :user, skip: [:registrations]
  root to: 'home#index'

  authenticate :user do
    mount Sidekiq::Web => '/sidekiq'
  end

  resources :dashboard, only: [:index] do
    collection do

    end
  end

  resources :orders

  resources :users

  resources :profiles

  resources :attempts, only: [:index] do
    collection do
      get :verify_attempts
    end
  end

  namespace :integrations do
    scope :greatpages do
      post :webhook, to: 'great_pages#webhook'
      get  :verify,  to: 'great_pages#verify'
    end
  end

  resources :leads, only: [:index] do
    collection do
      get :export
    end
  end

end
