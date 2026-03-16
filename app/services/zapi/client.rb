class Zapi::Client
  include HTTParty

  base_uri 'https://api.z-api.io'

  INSTANCE_ID = ENV.fetch('ZAPI_INSTANCE_ID')
  INSTANCE_TOKEN = ENV.fetch('ZAPI_INSTANCE_TOKEN')
  CLIENT_TOKEN = ENV.fetch('ZAPI_CLIENT_TOKEN')

  def self.send_text(phone:, message:)
    response = post(
      "/instances/#{INSTANCE_ID}/token/#{INSTANCE_TOKEN}/send-text",
      headers:,
      body: {
        phone:,
        message:
      }.to_json
    )

    response.parsed_response
  rescue StandardError => e
    Rails.logger.error("[ZAPI] erro ao enviar mensagem: #{e.message}")
    nil
  end

  def self.headers
    {
      'Content-Type' => 'application/json',
      'Client-Token' => CLIENT_TOKEN
    }
  end
end