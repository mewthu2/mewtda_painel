class Goal < ApplicationRecord
  belongs_to :client

  validates :year, presence: true
  validates :month, presence: true, inclusion: { in: 1..12 }
  validates :year, uniqueness: { scope: %i[client_id month] }

  %i[revenue_target roas_target avg_ticket_target conversion_rate_target
     cac_target tagged_revenue_target].each do |field|
    validates field, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  end
end
