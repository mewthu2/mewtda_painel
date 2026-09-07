class Popup < ApplicationRecord
  belongs_to :client
  has_one_attached :image
  has_many :popup_submissions, dependent: :destroy

  TEMPLATES = %w[template_1 template_2 template_3 template_4].freeze
  SIZES = %w[small medium large].freeze

  # Host fixo usado no snippet do script (app/views/popups/edit.html.erb) —
  # o widget deve sempre apontar para o domínio público real, mesmo quando o
  # snippet é gerado a partir do painel rodando em localhost ou staging.
  WIDGET_HOST = 'https://www.mewtda.com.br'.freeze

  before_create :generate_public_token

  validates :template, inclusion: { in: TEMPLATES }
  validates :size, inclusion: { in: SIZES }
  validates :reappear_after_hours, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :accent_color, format: { with: /\A#[0-9a-fA-F]{6}\z/ }, allow_blank: true
  validates :title, :coupon_code, :button_text, presence: true, if: :active?

  private

  def generate_public_token
    self.public_token ||= SecureRandom.hex(16)
  end
end
