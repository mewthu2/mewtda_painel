class Client < ApplicationRecord
  belongs_to :user
  has_many :integration_users, dependent: :destroy

  validates :name, presence: true
  validates :email, presence: true
end