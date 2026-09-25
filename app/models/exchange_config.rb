class ExchangeConfig < ApplicationRecord
  belongs_to :client
  has_one_attached :logo
  has_one_attached :requested_email_image
  has_one_attached :approved_email_image
  has_one_attached :rejected_email_image
  has_one_attached :completed_email_image

  # Conteúdo inicial dos 4 e-mails — evita que o cliente comece com campos em
  # branco; ele edita livremente depois em /crm/exchange_config/email_templates.
  DEFAULT_EMAIL_CONTENT = {
    requested: {
      subject: 'Recebemos sua solicitação de troca/devolução',
      body: "Olá {{customer_name}},\n\nRecebemos sua solicitação para o pedido {{order_number}}. " \
            "Nossa equipe vai analisar e te avisamos assim que tiver uma resposta.\n\nObrigado!"
    },
    approved: {
      subject: 'Sua solicitação foi aprovada!',
      body: "Olá {{customer_name}},\n\nSua solicitação para o pedido {{order_number}} foi aprovada.\n\n" \
            "Use o cupom {{coupon_code}} na sua próxima compra.\n\nObrigado!"
    },
    rejected: {
      subject: 'Sobre sua solicitação de troca/devolução',
      body: "Olá {{customer_name}},\n\nAnalisamos sua solicitação para o pedido {{order_number}} e, " \
            "infelizmente, não foi possível aprová-la dessa vez.\n\nQualquer dúvida, fale com a gente."
    },
    completed: {
      subject: 'Sua troca/devolução foi concluída',
      body: "Olá {{customer_name}},\n\nSua solicitação para o pedido {{order_number}} foi concluída.\n\n" \
            'Obrigado por comprar com a gente!'
    }
  }.freeze

  before_create :generate_slug
  before_create :apply_default_email_content

  validates :accent_color, format: { with: /\A#[0-9a-fA-F]{6}\z/ }, allow_blank: true
  validates :return_window_days, numericality: { only_integer: true, greater_than: 0 }
  validates :coupon_validity_days, numericality: { only_integer: true, greater_than: 0 }
  validates :company_name, presence: true, if: :active?

  private

  def apply_default_email_content
    DEFAULT_EMAIL_CONTENT.each do |kind, content|
      self[:"#{kind}_email_subject"] ||= content[:subject]
      self[:"#{kind}_email_body"] ||= content[:body]
    end
  end

  # Slug legível a partir do nome do cliente (ex.: "Loja Teste" -> "loja-teste"),
  # igual ao padrão já usado em Location (ver Shopify::Orders). Se colidir com
  # outro cliente de mesmo nome, desempata com o client_id (estável e único).
  def generate_slug
    return if slug.present?

    base = client.name.to_s.parameterize
    self.slug = ExchangeConfig.exists?(slug: base) ? "#{base}-#{client_id}" : base
  end
end
