class ManageIQ::Providers::Workflows::AutomationManager::Workflow < Workflow
  def run_queue(userid: "admin", inputs: {})
    instance = workflow_instances.create!(
      :ext_management_system => ext_management_system,
      :type                  => "#{ext_management_system.class}::WorkflowInstance",
      :userid                => userid,
      :context               => {"global" => inputs},
      :status                => "pending"
    )

    instance.run_queue
  end
end
