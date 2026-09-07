require 'test_helper'

class PopupsControllerTest < ActionDispatch::IntegrationTest
  def build_user(admin: false, client: nil)
    profile_id = admin ? Profile::ADMIN : Profile::USER
    Profile.find_or_create_by!(id: profile_id) { |p| p.name = admin ? 'Admin' : 'User' }

    User.create!(
      name: 'User', email: "user-#{SecureRandom.hex(4)}@example.com",
      password: 'password123', password_confirmation: 'password123',
      profile_id: profile_id, client: client
    )
  end

  def build_client
    Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
  end

  test 'the Marketing sidebar menu shows an active Pop Up link instead of the Campanhas placeholder' do
    client = build_client
    user = build_user(client: client)
    sign_in user

    get crm_path

    assert_response :success
    assert_match %r{href="#{Regexp.escape(edit_popup_path)}"}, response.body
    assert_match 'Pop Up', response.body
    # "Em breve" só existe hoje no placeholder desabilitado de Campanhas em
    # Marketing (confirmado via grep) — não usar "Campanhas" aqui, porque essa
    # palavra também aparece, sem relação nenhuma, no índice de busca da navbar
    # (HeaderHelper#searchable_nav_items, item "Campanhas" -> campaigns_path).
    assert_no_match 'Em breve', response.body
  end

  test 'edit shows the form for a client with no popup yet' do
    client = build_client
    user = build_user(client: client)
    sign_in user

    get edit_popup_path

    assert_response :success
    assert_match 'Pop-up de Cadastro', response.body
  end

  test 'edit does not show the embed snippet before the popup has been saved' do
    client = build_client
    user = build_user(client: client)
    sign_in user

    get edit_popup_path

    assert_no_match 'data-token', response.body
  end

  test 'update creates the popup and shows the embed snippet with its public_token' do
    client = build_client
    user = build_user(client: client)
    sign_in user

    patch popup_path, params: {
      popup: {
        title: 'Ganhe 10%', description: 'Cadastre-se', coupon_code: 'BEMVINDO10',
        button_text: 'Quero meu cupom', accent_color: '#ff0000',
        template: 'template_2', size: 'large', reappear_after_hours: 48, active: '1'
      }
    }

    client.reload
    assert client.popup.present?
    assert_equal 'BEMVINDO10', client.popup.coupon_code
    assert_redirected_to edit_popup_path

    follow_redirect!
    # O snippet é escrito na view como HTML já escapado (para aparecer como texto
    # visível dentro de <pre><code>), então as aspas chegam como &quot; no corpo
    # da resposta em vez de aspas literais.
    assert_match "data-token=&quot;#{client.popup.public_token}&quot;", response.body
  end

  test 'update rejects activating without a title' do
    client = build_client
    user = build_user(client: client)
    sign_in user

    patch popup_path, params: { popup: { active: '1', coupon_code: 'X', button_text: 'Y' } }

    assert_response :unprocessable_entity
    assert_nil client.reload.popup
  end

  test 'submissions lists entries for the client popup, most recent first' do
    client = build_client
    popup = Popup.create!(client: client)
    older = popup.popup_submissions.create!(name: 'Ana', email: 'ana@example.com', status: 'success', created_at: 2.days.ago)
    newer = popup.popup_submissions.create!(name: 'Beto', email: 'beto@example.com', status: 'shopify_error', created_at: 1.hour.ago)
    user = build_user(client: client)
    sign_in user

    get submissions_popup_path

    assert_response :success
    assert_operator response.body.index('Beto'), :<, response.body.index('Ana')
  end

  test 'submissions filters by status' do
    client = build_client
    popup = Popup.create!(client: client)
    popup.popup_submissions.create!(name: 'Ana', email: 'ana@example.com', status: 'success')
    popup.popup_submissions.create!(name: 'Beto', email: 'beto@example.com', status: 'shopify_error')
    user = build_user(client: client)
    sign_in user

    get submissions_popup_path(status: 'shopify_error')

    assert_response :success
    assert_match 'Beto', response.body
    assert_no_match 'Ana', response.body
  end

  test 'submissions shows an empty state when the client has no popup yet' do
    client = build_client
    user = build_user(client: client)
    sign_in user

    get submissions_popup_path

    assert_response :success
    assert_match 'Nenhum cadastro', response.body
  end
end
