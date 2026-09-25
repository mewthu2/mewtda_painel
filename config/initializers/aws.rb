# Credenciais globais da AWS (conta única do mewtda) usadas pelo
# Ses::DomainIdentityService pra verificar domínios de e-mail dos clientes.
# Cada cliente configura o próprio domínio de envio, mas a conta AWS por
# trás é sempre a mesma — não é algo configurável pelo painel.
if ENV['AWS_SES_ACCESS_KEY_ID'].present?
  Aws.config.update(
    region: ENV.fetch('AWS_SES_REGION', 'us-east-1'),
    credentials: Aws::Credentials.new(ENV['AWS_SES_ACCESS_KEY_ID'], ENV['AWS_SES_SECRET_ACCESS_KEY'])
  )
end
