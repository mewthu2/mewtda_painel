require 'test_helper'

class PopupSubmissionTest < ActiveSupport::TestCase
  def build_popup
    client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
    Popup.create!(client: client)
  end

  test 'valid with name, email and a known status' do
    submission = PopupSubmission.new(popup: build_popup, name: 'Ana', email: 'ana@example.com', status: 'success')
    assert submission.valid?
  end

  test 'invalid without a name' do
    submission = PopupSubmission.new(popup: build_popup, email: 'ana@example.com', status: 'success')
    assert_not submission.valid?
  end

  test 'invalid without an email' do
    submission = PopupSubmission.new(popup: build_popup, name: 'Ana', status: 'success')
    assert_not submission.valid?
  end

  test 'invalid with an unknown status' do
    submission = PopupSubmission.new(popup: build_popup, name: 'Ana', email: 'ana@example.com', status: 'pending')
    assert_not submission.valid?
  end

  test 'a popup has many submissions' do
    popup = build_popup
    submission = PopupSubmission.create!(popup: popup, name: 'Ana', email: 'ana@example.com', status: 'success')

    assert_includes popup.popup_submissions, submission
  end
end
