class Refund < ApplicationRecord
  belongs_to :client
  belongs_to :order, optional: true
end
