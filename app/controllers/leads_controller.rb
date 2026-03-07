class LeadsController < ApplicationController
  require 'csv'

  def index
    @leads = Lead.order(created_at: :desc)
                 .paginate(page: params[:page], per_page: 20)

    if params[:search].present?
      q = "%#{params[:search]}%"
      @leads = @leads.where(
        'email ILIKE :q OR name ILIKE :q',
        q: q
      )
    end
  end

  def export
    leads = Lead.order(created_at: :desc)

    csv = CSV.generate(headers: true) do |csv|
      csv << %w[id email name source created_at]

      leads.each do |lead|
        csv << [
          lead.id,
          lead.email,
          lead.name,
          lead.source,
          lead.created_at.strftime('%d/%m/%Y %H:%M')
        ]
      end
    end

    send_data csv,
      filename: "leads-#{Date.today}.csv",
      type: 'text/csv'
  end
end
