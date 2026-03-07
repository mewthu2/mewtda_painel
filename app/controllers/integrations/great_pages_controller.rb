# frozen_string_literal: true

module Integrations
  class GreatPagesController < IntegrationController

    def webhook
      lead = Lead.create!(
        email: params["E_mail"],
        name: params["Nome"],
        source: "greatpages",

        privacy_policy: params["Politicas_de_privacidade"],
        ip_address: params["IP_do_usuario"],
        conversion_at: params["Data_da_conversao"],
        device: params["Dispositivo"],
        referral_source: params["Referral_Source"],
        page_url: params["URL"],

        greatpages_page_id: params["Id_da_pagina"],
        greatpages_form_id: params["Id_do_formulario"],

        user_country: params["Pais_do_usuario"],
        user_region: params["Regiao_do_usuario"],
        user_city: params["Cidade_do_usuario"],

        experiment_id: params["Id_do_experimento"],
        variation_id: params["Id_da_variacao"],

        metadata: params.except(:controller, :action)
      )

      render json: { status: "ok", lead_id: lead.id }
    end

    def verify
      render json: {
        integration: current_integration.slug,
        status: "connected",
        received_at: Time.current
      }
    end
  end
end
