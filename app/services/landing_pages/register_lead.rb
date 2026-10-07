module LandingPages
  # Cadastra um lead vindo de uma landing page.
  #
  # Antes de criar o cliente na Shopify, verifica se a pessoa já está na base
  # (Shopify por e-mail/telefone, e a base local de customers da loja). Se já
  # estiver, só adiciona a tag da página no customer existente; se não, cria
  # com a tag. O lead é gravado de qualquer forma, marcando existing_customer.
  class RegisterLead
    Result = Struct.new(:lead, :created, keyword_init: true)

    def initialize(landing_page)
      @landing_page = landing_page
      @client = landing_page.client
    end

    def call(name:, email:, phone: nil, utms: {})
      email = email.to_s.strip.downcase
      phone = phone.to_s.strip

      existing_lead = @landing_page.leads.find_by(email: email)
      return Result.new(lead: existing_lead, created: false) if existing_lead

      lead = @landing_page.leads.new(
        name: name.to_s.strip, email: email, phone: phone.presence, status: 'success',
        **utms.to_h.symbolize_keys.slice(*LandingPageLead::UTM_FIELDS.map(&:to_sym))
      )
      return Result.new(lead: lead, created: false) unless lead.valid?

      sync = sync_with_shopify(lead)
      lead.assign_attributes(
        existing_customer: sync[:existing] || in_local_base?(email, phone),
        shopify_customer_id: sync[:customer_id],
        status: sync[:ok] ? 'success' : 'shopify_error'
      )
      lead.save
      Result.new(lead: lead, created: lead.persisted?)
    rescue ActiveRecord::RecordNotUnique
      Result.new(lead: @landing_page.leads.find_by(email: email), created: false)
    end

    private

    def in_local_base?(email, phone)
      scope = Customer.joins(:orders).where(orders: { client_id: @client.id })
      return true if scope.where('LOWER(customers.email) = ?', email).exists?

      phone.present? && scope.where(customers: { phone: phone }).exists?
    end

    def sync_with_shopify(lead)
      return { ok: false, existing: false, customer_id: nil } unless @client.shopify_configured?

      shopify = Shopify::Client.new(@client)
      existing_id = find_customer_id(shopify, lead)

      if existing_id
        add_tag(shopify, existing_id)
        { ok: true, existing: true, customer_id: existing_id }
      else
        create_customer(shopify, lead)
      end
    rescue StandardError => e
      Rails.logger.error("[LandingPages::RegisterLead] lp #{@landing_page.id}: #{e.class} #{e.message}")
      { ok: false, existing: false, customer_id: nil }
    end

    def find_customer_id(shopify, lead)
      terms = ["email:#{lead.email}"]
      terms << "phone:#{e164(lead.phone)}" if e164(lead.phone)

      terms.each do |term|
        data = shopify.query(<<~GRAPHQL)
          {
            customers(first: 1, query: #{term.inspect}) {
              edges { node { id } }
            }
          }
        GRAPHQL
        id = data.dig('customers', 'edges', 0, 'node', 'id')
        return id if id
      end
      nil
    end

    # A Shopify só aceita telefone em E.164. Número brasileiro digitado sem DDI
    # (10–11 dígitos) ganha o +55; qualquer coisa estranha é ignorada.
    def e164(phone)
      digits = phone.to_s.gsub(/\D/, '')
      return nil if digits.blank?
      return "+55#{digits}" if digits.length.between?(10, 11)
      return "+#{digits}" if digits.length.between?(12, 13) && digits.start_with?('55')

      nil
    end

    def add_tag(shopify, customer_id)
      shopify.query(<<~GRAPHQL)
        mutation {
          tagsAdd(id: #{customer_id.inspect}, tags: [#{@landing_page.lead_tag.inspect}]) {
            userErrors { field message }
          }
        }
      GRAPHQL
    end

    def create_customer(shopify, lead)
      first, last = lead.name.split(' ', 2)
      fields = ["email: #{lead.email.inspect}", "tags: [#{@landing_page.lead_tag.inspect}]"]
      fields << "firstName: #{first.to_s.inspect}" if first.present?
      fields << "lastName: #{last.to_s.inspect}" if last.present?
      fields << "phone: #{e164(lead.phone).inspect}" if e164(lead.phone)

      data = shopify.query(<<~GRAPHQL)
        mutation {
          customerCreate(input: { #{fields.join(', ')} }) {
            customer { id }
            userErrors { field message }
          }
        }
      GRAPHQL

      payload = data['customerCreate'] || {}
      errors = payload['userErrors'] || []
      if errors.empty?
        { ok: true, existing: false, customer_id: payload.dig('customer', 'id') }
      else
        Rails.logger.warn("[LandingPages::RegisterLead] customerCreate: #{errors.map { |e| e['message'] }.join(', ')}")
        # Telefone inválido é o caso mais comum: tenta de novo sem telefone.
        return create_customer(shopify, lead.dup.tap { |l| l.phone = nil }) if e164(lead.phone)

        { ok: false, existing: false, customer_id: nil }
      end
    end
  end
end
