module Ses
  class DomainIdentityService
    def initialize(client, ses: Aws::SESV2::Client.new)
      @client = client
      @ses = ses
    end

    # Cria a identidade de domínio na SES (Easy DKIM) e guarda os tokens
    # retornados — cada um vira um registro CNAME que o cliente precisa
    # cadastrar no DNS pra provar a propriedade do domínio e habilitar o DKIM.
    def create!
      response = @ses.create_email_identity(email_identity: @client.email_sending_domain)
      tokens = response.dkim_attributes.tokens

      @client.update!(ses_dkim_tokens: tokens, ses_verification_status: 'pending', ses_verified_at: nil)
      tokens
    end

    # Consulta o status atual na SES e atualiza o cliente de acordo.
    def refresh_status!
      response = @ses.get_email_identity(email_identity: @client.email_sending_domain)
      verified = response.verified_for_sending_status

      @client.update!(
        ses_verification_status: verified ? 'verified' : 'pending',
        ses_verified_at: verified ? Time.current : nil
      )
      verified
    end
  end
end
