Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins '*'

    resource '/integrations/*',
      headers: :any,
      methods: [:post, :options],
      expose: ['Authorization'],
      max_age: 600
  end
end