require 'test_helper'

class TrackingReportChannelTest < ActionCable::Channel::TestCase
  include ActiveJob::TestHelper

  def setup
    @client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
    profile = Profile.find_or_create_by!(id: Profile::ADMIN) { |p| p.name = 'Admin' }
    @user = User.create!(name: 'Admin', email: "admin-#{SecureRandom.hex(4)}@example.com",
                         password: 'password123', password_confirmation: 'password123', profile_id: profile.id)
    @token = Tracking::ReportToken.generate(user: @user, client: @client, period: '7')
  end

  test 'subscribes with a valid token and enqueues the report on start' do
    stub_connection current_user: @user
    subscribe token: @token

    assert subscription.confirmed?
    assert_has_stream TrackingReportChannel.stream_name(@token)

    assert_enqueued_with(job: TrackingReportJob,
                         args: [TrackingReportChannel.stream_name(@token), @client.id, '7', nil, nil]) do
      perform :start
    end
  end

  test 'rejects a token issued to another user' do
    other = User.create!(name: 'Outro', email: "outro-#{SecureRandom.hex(4)}@example.com",
                         password: 'password123', password_confirmation: 'password123', profile_id: @user.profile_id)
    stub_connection current_user: other
    subscribe token: @token

    assert subscription.rejected?
  end

  test 'rejects a forged token' do
    stub_connection current_user: @user
    subscribe token: 'forjado'

    assert subscription.rejected?
  end
end
