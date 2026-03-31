class Campaign < ApplicationRecord
  belongs_to :client
  has_many :campaign_actions, dependent: :destroy

  enum kind: {
    cashback: 0,
    cashback_expiration: 1
  }

  validates :name, presence: true
  validates :kind, presence: true
  validates :message, presence: true
  validates :days_after_purchase, presence: true, numericality: { greater_than: 0 }
  validates :start_date, presence: true
  validates :end_date, presence: true
  validate :end_date_after_start_date

  scope :active, -> { where(active: true) }
  scope :running, -> { active.where('start_date <= ? AND end_date >= ?', Date.current, Date.current) }

  def running?
    active? && start_date <= Date.current && end_date >= Date.current
  end

  def zapi_configured?
    client&.zapi_instance_id.present? &&
      client&.zapi_instance_token.present? &&
      client&.zapi_client_token.present?
  end

  def status
    return :inactive unless active?
    return :pending  if start_date > Date.current
    return :finished if end_date < Date.current
    :running
  end

  def kind_label
    case kind
    when 'cashback'           then 'Cashback'
    when 'cashback_expiration' then 'Expiração de Cashback'
    else kind
    end
  end

  def days_after_purchase_label
    cashback_expiration? ? 'dias antes da expiração' : 'dias após a compra'
  end

  def actions_count = campaign_actions.count
  def sent_count    = campaign_actions.sent.count
  def pending_count = campaign_actions.pending.count
  def failed_count  = campaign_actions.failed.count

  private

  def end_date_after_start_date
    return if start_date.blank? || end_date.blank?
    errors.add(:end_date, 'deve ser posterior à data de início') if end_date < start_date
  end
end