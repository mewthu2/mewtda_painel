class IntegrationUser < ApplicationRecord
  belongs_to :client

  before_create :generate_api_secret

  validates :slug, presence: true

  private

  def generate_api_secret
    self.api_secret ||= SecureRandom.hex(64)
  end
end