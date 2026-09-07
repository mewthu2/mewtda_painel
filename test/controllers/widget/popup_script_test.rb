require 'test_helper'

class Widget::PopupScriptTest < ActionDispatch::IntegrationTest
  test 'the embeddable script is served and reads its own data-token' do
    get '/widget/popup.js'

    assert_response :success
    assert_match 'data-token', response.body
    assert_match '/widget/popup/config', response.body
    assert_match '/widget/popup/submissions', response.body
  end
end
