class ManageIQ::Providers::Workflows::AutomationManager::Workflow < Workflow
  def execute(userid = "admin", inputs = {})
    require "manageiq-floe"
    floe = ManageIQ::Floe::Workflow.new(payload)

    context = {
      "global"        => inputs,
      "current_state" => floe.start_at,
      "states"        => []
    }

    instance = workflow_instances.create!(
      :ext_management_system => ext_management_system,
      :type                  => "#{ext_management_system.class}::WorkflowInstance",
      :userid                => userid,
      :context               => context,
      :status                => "pending"
    )

    instance.run_queue
  end
end
