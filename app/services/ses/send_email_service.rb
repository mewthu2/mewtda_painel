module Ses
  class SendEmailService
    def initialize(client, ses: Aws::SESV2::Client.new)
      @client = client
      @ses = ses
    end

    def call(to:, subject:, html_body:)
      return false unless @client.ses_domain_verified?

      @ses.send_email(
        from_email_address: "naoresponda@#{@client.email_sending_domain}",
        destination: { to_addresses: [to] },
        content: {
          simple: {
            subject: { data: subject },
            body: { html: { data: html_body } }
          }
        }
      )
      true
    end
  end
end
