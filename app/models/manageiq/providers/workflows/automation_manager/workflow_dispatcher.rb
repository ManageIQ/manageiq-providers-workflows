class ManageIQ::Providers::Workflows::AutomationManager::WorkflowDispatcher < MiqQueueWorkerBase
  include MiqWorker::ReplicaPerWorker

  require_nested :Runner

  self.required_roles     = %w[embedded_workflows]
  self.default_queue_name = "workflows"

  def self.kill_priority
    MiqWorkerType::KILL_PRIORITY_GENERIC_WORKERS
  end

  def self.settings_name
    :workflows_dispatcher
  end
end
