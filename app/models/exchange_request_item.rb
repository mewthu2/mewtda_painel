class ExchangeRequestItem < ApplicationRecord
  belongs_to :exchange_request
  has_one_attached :photo

  enum kind: { troca: 0, devolucao: 1 }

  DEFECT_REASON = 'defeito'.freeze

  # Motivos plausíveis pra troca/devolução, oferecidos como select na tela
  # pública — evita texto livre e permite exigir foto só quando fizer sentido.
  REASONS = [
    ['tamanho_nao_serviu', 'Tamanho não serviu'],
    ['nao_gostei', 'Não gostei do produto'],
    ['arrependimento', 'Arrependimento da compra'],
    ['produto_errado', 'Veio um produto diferente do pedido'],
    [DEFECT_REASON, 'Produto com defeito ou avaria'],
    ['outro', 'Outro motivo']
  ].freeze

  validates :product_name, presence: true
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :price, numericality: { greater_than_or_equal_to: 0 }
  validates :reason, presence: true, inclusion: { in: REASONS.map(&:first) }
  validate :photo_required_for_defect

  def reason_label
    REASONS.to_h[reason] || reason
  end

  private

  def photo_required_for_defect
    return unless reason == DEFECT_REASON
    return if photo.attached?

    errors.add(:photo, 'é obrigatória quando o motivo é defeito ou avaria')
  end
end
