class ManageIQ::Providers::Workflows::AutomationManager::Workflow < ManageIQ::Providers::EmbeddedAutomationManager::ConfigurationScriptPayload
  def self.create_from_json!(json, **kwargs)
    json = JSON.parse(json) if json.kind_of?(String)
    name = json["Comment"]

    workflows_automation_manager = ManageIQ::Providers::Workflows::AutomationManager.first
    create!(:manager => workflows_automation_manager, :name => name, :payload => json, **kwargs)
  end

  def execute(run_by_userid: "admin", inputs: {})
    require "floe"
    floe = Floe::Workflow.new(payload)

    context = {
      "global"        => inputs,
      "current_state" => floe.start_at,
      "states"        => []
    }

    miq_task = instance = nil
    transaction do
      miq_task = MiqTask.create!(
        :name   => "Execute Workflow",
        :userid => run_by_userid
      )

      instance = children.create!(
        :manager       => manager,
        :type          => "#{manager.class}::WorkflowInstance",
        :run_by_userid => run_by_userid,
        :miq_task      => miq_task,
        :payload       => payload,
        :credentials   => credentials,
        :context       => context,
        :output        => context["global"],
        :status        => "pending"
      )

      miq_task.update!(:context_data => {:workflow_instance_id => instance.id})
    end

    instance.run_queue

    miq_task.id
  end
end
