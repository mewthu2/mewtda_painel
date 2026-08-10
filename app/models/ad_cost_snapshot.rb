class AdCostSnapshot < ApplicationRecord
  belongs_to :client

  PLATFORMS = %w[google_ads meta].freeze

  validates :platform, inclusion: { in: PLATFORMS }
  validates :year, presence: true
  validates :month, presence: true, inclusion: { in: 1..12 }
  validates :cost, numericality: { greater_than_or_equal_to: 0 }
  validates :platform, uniqueness: { scope: %i[client_id year month] }
end
