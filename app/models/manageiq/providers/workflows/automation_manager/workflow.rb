class ManageIQ::Providers::Workflows::AutomationManager::Workflow < ManageIQ::Providers::EmbeddedAutomationManager::ConfigurationScriptPayload
  def self.create_from_json!(json, **kwargs)
    json = JSON.parse(json) if json.kind_of?(String)
    name = json["Comment"]

    workflows_automation_manager = ManageIQ::Providers::Workflows::AutomationManager.first
    create!(:manager => workflows_automation_manager, :name => name, :payload => JSON.pretty_generate(json), :payload_type => "json", **kwargs)
  end

  def run(inputs: {}, userid: "system", zone: nil, role: "automate", object: nil)
    raise _("execute is not enabled") unless Settings.prototype.ems_workflows.enabled

    require "floe"
    context = Floe::Workflow::Context.new(:input => inputs)

    miq_task = instance = nil
    transaction do
      miq_task = MiqTask.create!(
        :name   => "Execute Workflow",
        :userid => userid
      )

      instance = children.create!(
        :manager       => manager,
        :type          => "#{manager.class}::WorkflowInstance",
        :run_by_userid => userid,
        :miq_task      => miq_task,
        :payload       => payload,
        :credentials   => credentials,
        :context       => context.to_h,
        :output        => inputs,
        :status        => "pending"
      )

      miq_task.update!(:context_data => {:workflow_instance_id => instance.id})
    end

    instance.run_queue(:zone => zone, :role => role, :object => object)

    miq_task.id
  end
end
