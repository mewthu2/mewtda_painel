class Coupouns::GenerateCashbackCode
  CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'.freeze

  def self.call(order_number)
    order_number = order_number.to_s.gsub('#', '')

    random_code = ''

    6.times do |i|
      seed = rand(CHARS.length) + order_number[i % order_number.length].ord
      random_code += CHARS[seed % CHARS.length]
    end

    "HENRRI#{random_code}#{order_number}"
  end
end