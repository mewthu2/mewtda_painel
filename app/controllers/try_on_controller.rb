require 'net/http'
require 'uri'
require 'json'
require 'base64'
require 'openssl'

class TryOnController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin!

  def index
    # View de upload
  end

  def create
    mode = params[:mode] || 'tryon'

    case mode
    when 'tryon'
      process_tryon
    when 'product_to_model'
      process_product_to_model
    when 'tryon_v16'
      process_tryon_v16
    else
      render json: { error: 'Modo inválido' }, status: :unprocessable_entity
    end
  end

  def status
    prediction_id = params[:prediction_id]

    unless prediction_id
      render json: { error: 'ID da predição é obrigatório' }, status: :unprocessable_entity
      return
    end

    response = check_fashn_status(prediction_id)
    render json: response
  end

  private

  def require_admin!
    unless current_user.admin?
      redirect_to crm_path, alert: 'Acesso negado. Apenas administradores podem acessar esta funcionalidade.'
    end
  end

  # ============================================
  # MODO 1: TRY-ON (produto + modelo obrigatórios)
  # ============================================
  def process_tryon
    product_image = params[:product_image]
    model_image = params[:model_image]

    unless product_image && model_image
      render json: { error: 'Imagens do produto e modelo são obrigatórias' }, status: :unprocessable_entity
      return
    end

    product_base64 = image_to_base64(product_image)
    model_base64 = image_to_base64(model_image)

    response = call_fashn_api('tryon-max', {
                                product_image: product_base64,
                                model_image: model_base64
                              })

    if response[:error]
      render json: { error: response[:error] }, status: :unprocessable_entity
    else
      render json: { prediction_id: response[:id] }
    end
  end

  # ============================================
  # MODO 2: PRODUCT TO MODEL
  # ============================================
  def process_product_to_model
    product_image = params[:product_image]

    unless product_image
      render json: { error: 'Imagem do produto é obrigatória' }, status: :unprocessable_entity
      return
    end

    inputs = {
      product_image: image_to_base64(product_image)
    }

    # Parâmetros opcionais
    if params[:model_image].present?
      inputs[:model_image] = image_to_base64(params[:model_image])
    end

    if params[:face_reference].present?
      inputs[:face_reference] = image_to_base64(params[:face_reference])
    end

    if params[:face_reference_mode].present?
      inputs[:face_reference_mode] = params[:face_reference_mode]
    end

    if params[:image_prompt].present?
      inputs[:image_prompt] = image_to_base64(params[:image_prompt])
    end

    if params[:background_reference].present?
      inputs[:background_reference] = image_to_base64(params[:background_reference])
    end

    if params[:prompt].present?
      inputs[:prompt] = params[:prompt]
    end

    if params[:aspect_ratio].present?
      inputs[:aspect_ratio] = params[:aspect_ratio]
    end

    if params[:resolution].present?
      inputs[:resolution] = params[:resolution]
    end

    if params[:generation_mode].present?
      inputs[:generation_mode] = params[:generation_mode]
    end

    if params[:num_images].present?
      inputs[:num_images] = params[:num_images].to_i
    end

    if params[:output_format].present?
      inputs[:output_format] = params[:output_format]
    end

    if params[:seed].present?
      inputs[:seed] = params[:seed].to_i
    end

    response = call_fashn_api('product-to-model', inputs)

    if response[:error]
      render json: { error: response[:error] }, status: :unprocessable_entity
    else
      render json: { prediction_id: response[:id] }
    end
  end

  # ============================================
  # MODO 3: TRYON V1.6 (E-COMMERCE)
  # ============================================
  def process_tryon_v16
    model_image = params[:model_image]
    garment_image = params[:garment_image]

    unless model_image && garment_image
      render json: { error: 'Imagens do modelo e da peça são obrigatórias' }, status: :unprocessable_entity
      return
    end

    inputs = {
      model_image: image_to_base64(model_image),
      garment_image: image_to_base64(garment_image)
    }

    inputs[:category] = params[:v16_category] if params[:v16_category].present?
    inputs[:mode] = params[:v16_mode] if params[:v16_mode].present?
    inputs[:garment_photo_type] = params[:v16_garment_photo_type] if params[:v16_garment_photo_type].present?
    inputs[:num_samples] = params[:v16_num_samples].to_i if params[:v16_num_samples].present?
    inputs[:output_format] = params[:v16_output_format] if params[:v16_output_format].present?
    inputs[:moderation_level] = params[:v16_moderation] if params[:v16_moderation].present?

    response = call_fashn_api('tryon-v1.6', inputs)

    if response[:error]
      render json: { error: response[:error] }, status: :unprocessable_entity
    else
      render json: { prediction_id: response[:id] }
    end
  end

  # ============================================
  # HELPERS
  # ============================================
  def image_to_base64(image)
    if image.is_a?(ActionDispatch::Http::UploadedFile)
      content_type = image.content_type
      image.rewind
      encoded = Base64.strict_encode64(image.read)
      "data:#{content_type};base64,#{encoded}"
    elsif image.is_a?(String) && image.start_with?('http')
      image
    else
      image
    end
  end

  def create_http_client(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http.ssl_version = :TLSv1_2
    http.open_timeout = 30
    http.read_timeout = 180
    http.write_timeout = 180 if http.respond_to?(:write_timeout=)
    http.min_version = OpenSSL::SSL::TLS1_2_VERSION if http.respond_to?(:min_version=)
    http
  end

  def call_fashn_api(model_name, inputs)
    uri = URI('https://api.fashn.ai/v1/run')

    http = create_http_client(uri)

    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request['Authorization'] = "Bearer #{ENV['FASHN_API_KEY']}"
    request['Accept'] = 'application/json'

    body = {
      model_name: model_name,
      inputs: inputs
    }

    request.body = body.to_json

    Rails.logger.info "[FASHN] Enviando requisição para #{uri} - Model: #{model_name}"
    Rails.logger.info "[FASHN] Tamanho do body: #{request.body.bytesize} bytes"

    response = http.request(request)

    Rails.logger.info "[FASHN] Response status: #{response.code}"
    Rails.logger.info "[FASHN] Response body: #{response.body[0..500]}"

    parsed = JSON.parse(response.body, symbolize_names: true)

    if response.code.to_i >= 400
      { error: parsed[:error] || parsed[:message] || "Erro HTTP #{response.code}" }
    else
      parsed
    end
  rescue Net::OpenTimeout, Net::ReadTimeout => e
    Rails.logger.error "[FASHN] Timeout Error: #{e.message}"
    { error: "Timeout na conexão com a API. Tente novamente." }
  rescue OpenSSL::SSL::SSLError => e
    Rails.logger.error "[FASHN] SSL Error: #{e.message}"
    retry_with_alternative_ssl(model_name, inputs)
  rescue JSON::ParserError => e
    Rails.logger.error "[FASHN] JSON Parse Error: #{e.message}"
    { error: "Resposta inválida da API" }
  rescue => e
    Rails.logger.error "[FASHN] API Error: #{e.class} - #{e.message}"
    { error: "Erro ao conectar com a API: #{e.message}" }
  end

  def retry_with_alternative_ssl(model_name, inputs)
    Rails.logger.info "[FASHN] Tentando conexão alternativa..."

    uri = URI('https://api.fashn.ai/v1/run')

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    http.open_timeout = 30
    http.read_timeout = 180

    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request['Authorization'] = "Bearer #{ENV['FASHN_API_KEY']}"

    request.body = {
      model_name: model_name,
      inputs: inputs
    }.to_json

    response = http.request(request)
    JSON.parse(response.body, symbolize_names: true)
  rescue => e
    Rails.logger.error "[FASHN] Retry Error: #{e.message}"
    { error: "Erro de conexão SSL. Verifique sua versão do Ruby/OpenSSL." }
  end

  def check_fashn_status(prediction_id)
    uri = URI("https://api.fashn.ai/v1/status/#{prediction_id}")

    http = create_http_client(uri)

    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "Bearer #{ENV['FASHN_API_KEY']}"
    request['Accept'] = 'application/json'

    response = http.request(request)

    Rails.logger.info "[FASHN] Status response: #{response.body}"

    JSON.parse(response.body, symbolize_names: true)
  rescue OpenSSL::SSL::SSLError => e
    Rails.logger.error "[FASHN] SSL Error on status: #{e.message}"
    retry_status_alternative(prediction_id)
  rescue => e
    Rails.logger.error "[FASHN] Status Error: #{e.message}"
    { error: e.message }
  end

  def retry_status_alternative(prediction_id)
    uri = URI("https://api.fashn.ai/v1/status/#{prediction_id}")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "Bearer #{ENV['FASHN_API_KEY']}"

    response = http.request(request)
    JSON.parse(response.body, symbolize_names: true)
  rescue => e
    { error: e.message }
  end
end
