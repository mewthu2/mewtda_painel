module Shopify
  class CreateCustomer
    ALREADY_TAKEN_PATTERN = /taken/i

    def initialize(db_client)
      @db_client = db_client
    end

    def call(name:, email:, phone:)
      shopify = Shopify::Client.new(@db_client)
      data = shopify.query(build_mutation(name: name, email: email, phone: phone))
      payload = data['customerCreate'] || {}
      user_errors = payload['userErrors'] || []

      if user_errors.empty?
        { ok: true, customer_id: payload.dig('customer', 'id') }
      elsif user_errors.any? { |e| e['message'].to_s.match?(ALREADY_TAKEN_PATTERN) }
        { ok: true, customer_id: find_existing_customer_id(shopify, email) }
      else
        { ok: false, customer_id: nil }
      end
    rescue StandardError
      { ok: false, customer_id: nil }
    end

    private

    def build_mutation(name:, email:, phone:)
      fields = ["email: #{email.to_s.inspect}"]

      if name.present?
        first, last = name.to_s.strip.split(' ', 2)
        fields << "firstName: #{first.to_s.inspect}"
        fields << "lastName: #{last.to_s.inspect}" if last.present?
      end

      fields << "phone: #{phone.to_s.inspect}" if phone.present?

      <<~GRAPHQL
        mutation {
          customerCreate(input: { #{fields.join(', ')} }) {
            customer { id }
            userErrors { field message }
          }
        }
      GRAPHQL
    end

    def find_existing_customer_id(shopify, email)
      query = <<~GRAPHQL
        {
          customers(first: 1, query: #{"email:#{email}".inspect}) {
            edges { node { id } }
          }
        }
      GRAPHQL

      data = shopify.query(query)
      data.dig('customers', 'edges', 0, 'node', 'id')
    rescue StandardError
      nil
    end
  end
end
