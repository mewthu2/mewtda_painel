# Sem retry: uma nova tentativa automática poderia incluir uma segunda nota no
# Tiny. Se falhar, o erro fica na execução e a pessoa gera de novo pela tela.
class CustomAutomationBuildJob < ApplicationJob
  queue_as :default
  sidekiq_options retry: false if respond_to?(:sidekiq_options)

  def perform(run_id)
    run = CustomAutomationRun.find(run_id)
    return unless run.status == 'pending'

    CustomAutomations::FernandaFarahTransferNote.new(run).build!
  end
end
