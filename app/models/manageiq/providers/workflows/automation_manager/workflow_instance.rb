class ManageIQ::Providers::Workflows::AutomationManager::WorkflowInstance < WorkflowInstance
  def run_queue
    MiqQueue.put(
      :class_name  => self.class.name,
      :instance_id => id,
      :method_name => "run"
    )
  end

  def run
    wf = ManageIQ::Floe::Workflow.new(workflow.payload, context)
    wf.step
    update!(:context => wf.context, :status => wf.status)
    run_queue unless wf.end?
  end
end
