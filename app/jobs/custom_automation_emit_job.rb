class CustomAutomationEmitJob < ApplicationJob
  queue_as :default
  sidekiq_options retry: false if respond_to?(:sidekiq_options)

  def perform(run_id)
    run = CustomAutomationRun.find(run_id)
    return unless run.status == 'emitting'

    CustomAutomations::FernandaFarahTransferNote.new(run).emit!
  end
end
