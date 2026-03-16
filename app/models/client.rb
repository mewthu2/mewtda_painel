class Client < ApplicationRecord
  has_many :users
  has_many :integration_users, dependent: :destroy

  validates :name, presence: true
  validates :email, presence: true
end