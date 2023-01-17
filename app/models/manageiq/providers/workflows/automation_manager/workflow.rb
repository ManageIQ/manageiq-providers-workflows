class ManageIQ::Providers::Workflows::AutomationManager::Workflow < Workflow
  def execute(userid = "admin")
    require "manageiq-floe"
    floe = ManageIQ::Floe::Workflow.new(payload)

    context = {
      "global" => {},
      "states" => {
        "current_state" => floe.start_at
      }
    }

    floe.states.map(&:name).each do |state_name|
      context["states"][state_name] = []
    end

    instance = workflow_instances.create!(
      :ext_management_system => ext_management_system,
      :type                  => "#{ext_management_system.class}::WorkflowInstance",
      :userid                => userid,
      :context               => context
    )

    instance.run_queue
  end
end
