class AdCost < ApplicationRecord
  belongs_to :client

  PLATFORMS = %w[google_ads meta].freeze
  PLATFORM_LABELS = { 'google_ads' => 'Google Ads', 'meta' => 'Meta Ads' }.freeze

  validates :platform, inclusion: { in: PLATFORMS }
  validates :name, presence: true
  validates :start_date, presence: true
  validates :end_date, presence: true
  validates :amount, numericality: { greater_than_or_equal_to: 0 }
  validate :end_date_after_start_date

  scope :overlapping, ->(range_start, range_end) { where('start_date <= ? AND end_date >= ?', range_end, range_start) }

  def platform_label
    PLATFORM_LABELS[platform] || platform
  end

  private

  def end_date_after_start_date
    return if start_date.blank? || end_date.blank?

    errors.add(:end_date, 'deve ser igual ou posterior à data de início') if end_date < start_date
  end
end
