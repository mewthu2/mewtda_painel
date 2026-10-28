require 'test_helper'

class TrackingReportJobTest < ActiveJob::TestCase
  include ActionCable::TestHelper

  def setup
    @client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
    @integration_user = IntegrationUser.create!(
      name: 'Pixel', slug: "pixel-#{SecureRandom.hex(4)}", api_secret: SecureRandom.hex(8), client: @client
    )
  end

  def create_event(kind, session_id)
    ShopifyEvent.create!(client: @client, integration_user: @integration_user, kind: kind,
                         session_id: session_id, created_at: 1.hour.ago)
  end

  test 'broadcasts the rendered report with chart data' do
    create_event('page_viewed', 's1')
    create_event('product_viewed', 's1')
    create_event('checkout_completed', 's2')

    assert_broadcasts('tracking_report:abc', 1) do
      TrackingReportJob.perform_now('tracking_report:abc', @client.id, '7', nil, nil)
    end

    html = broadcasts('tracking_report:abc').last.then { |m| JSON.parse(m)['html'] }
    assert_includes html, 'db-chart-data'
    assert_includes html, 'Sessoes Recentes'
    assert_includes html, 'db-session-row'
  end

  test 'broadcasts the empty message when the period has no events' do
    TrackingReportJob.perform_now('tracking_report:empty', @client.id, '1', nil, nil)

    html = JSON.parse(broadcasts('tracking_report:empty').last)['html']
    assert_includes html, 'Nenhum evento encontrado'
  end

  test 'broadcasts an error instead of raising' do
    TrackingReportJob.perform_now('tracking_report:err', -1, '1', nil, nil)

    assert_equal 'Não foi possível carregar os dados. Tente novamente.',
                 JSON.parse(broadcasts('tracking_report:err').last)['error']
  end
end
