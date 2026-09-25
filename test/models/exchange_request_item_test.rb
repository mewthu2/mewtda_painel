require 'test_helper'

class ExchangeRequestItemTest < ActiveSupport::TestCase
  def build_exchange_request
    client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
    ExchangeRequest.create!(
      client: client, shopify_order_id: '1', shopify_order_number: '#1001',
      customer_email: 'ana@example.com'
    )
  end

  test 'valid with required fields' do
    item = ExchangeRequestItem.new(
      exchange_request: build_exchange_request, product_name: 'Camiseta P',
      quantity: 1, price: 99.9, kind: :troca, reason: 'tamanho_nao_serviu'
    )
    assert item.valid?, item.errors.full_messages.to_s
  end

  test 'requires product_name' do
    item = ExchangeRequestItem.new(
      exchange_request: build_exchange_request, quantity: 1, price: 10, kind: :troca, reason: 'outro'
    )
    assert_not item.valid?
    assert_includes item.errors.attribute_names, :product_name
  end

  test 'rejects a zero quantity' do
    item = ExchangeRequestItem.new(
      exchange_request: build_exchange_request, product_name: 'X', quantity: 0, price: 10, kind: :troca, reason: 'outro'
    )
    assert_not item.valid?
  end

  test 'rejects a negative price' do
    item = ExchangeRequestItem.new(
      exchange_request: build_exchange_request, product_name: 'X', quantity: 1, price: -1, kind: :troca, reason: 'outro'
    )
    assert_not item.valid?
  end

  test 'kind defaults to the troca/devolucao enum' do
    item = ExchangeRequestItem.new(kind: :devolucao)
    assert item.devolucao?
    assert_not item.troca?
  end

  test 'requires a reason' do
    item = ExchangeRequestItem.new(
      exchange_request: build_exchange_request, product_name: 'X', quantity: 1, price: 10, kind: :troca
    )
    assert_not item.valid?
    assert_includes item.errors.attribute_names, :reason
  end

  test 'rejects a reason outside the known list' do
    item = ExchangeRequestItem.new(
      exchange_request: build_exchange_request, product_name: 'X', quantity: 1, price: 10, kind: :troca,
      reason: 'motivo qualquer'
    )
    assert_not item.valid?
    assert_includes item.errors.attribute_names, :reason
  end

  test 'requires a photo when the reason is defeito' do
    item = ExchangeRequestItem.new(
      exchange_request: build_exchange_request, product_name: 'X', quantity: 1, price: 10, kind: :troca,
      reason: ExchangeRequestItem::DEFECT_REASON
    )
    assert_not item.valid?
    assert_includes item.errors.attribute_names, :photo
  end

  test 'does not require a photo for other reasons' do
    item = ExchangeRequestItem.new(
      exchange_request: build_exchange_request, product_name: 'X', quantity: 1, price: 10, kind: :troca,
      reason: 'nao_gostei'
    )
    assert item.valid?, item.errors.full_messages.to_s
  end

  test 'is valid with a photo attached when the reason is defeito' do
    item = ExchangeRequestItem.new(
      exchange_request: build_exchange_request, product_name: 'X', quantity: 1, price: 10, kind: :troca,
      reason: ExchangeRequestItem::DEFECT_REASON
    )
    item.photo.attach(io: StringIO.new('fake image data'), filename: 'defeito.png', content_type: 'image/png')

    assert item.valid?, item.errors.full_messages.to_s
  end
end
