class PopupSubmission < ApplicationRecord
  belongs_to :popup

  STATUSES = %w[success shopify_error].freeze

  validates :name, presence: true
  validates :email, presence: true
  validates :status, inclusion: { in: STATUSES }
end
