class Profile < ApplicationRecord
  has_many :user_profiles, dependent: :destroy
  has_many :users, through: :user_profiles

  validates :name, presence: true

  ADMIN = 1
  USER = 2
end
