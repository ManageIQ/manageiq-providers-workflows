class ManageIQ::Providers::Workflows::AutomationManager::Workflow < Workflow
  def execute(userid: "admin", inputs: {})
    require "manageiq-floe"
    floe = ManageIQ::Floe::Workflow.new(payload)

    context = {
      "global"        => inputs,
      "current_state" => floe.start_at,
      "states"        => []
    }

    miq_task = instance = nil
    transaction do
      miq_task = MiqTask.create!(
        :name   => "Execute Workflow",
        :userid => userid,
      )

      instance = workflow_instances.create!(
        :ext_management_system => ext_management_system,
        :type                  => "#{ext_management_system.class}::WorkflowInstance",
        :userid                => userid,
        :miq_task              => miq_task,
        :payload               => payload,
        :credentials           => credentials,
        :context               => context,
        :output                => context["global"],
        :status                => "pending",
      )

      miq_task.update!(:context_data => {:workflow_instance_id => instance.id})
    end

    instance.run_queue

    miq_task.id
  end
end
