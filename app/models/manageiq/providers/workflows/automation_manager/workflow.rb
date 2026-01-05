class ManageIQ::Providers::Workflows::AutomationManager::Workflow < ManageIQ::Providers::EmbeddedAutomationManager::ConfigurationScriptPayload
  def self.create_from_json!(json, **kwargs)
    json = JSON.parse(json) if json.kind_of?(String)
    name = json["Comment"]

    workflows_automation_manager = ManageIQ::Providers::Workflows::AutomationManager.first
    create!(:manager => workflows_automation_manager, :name => name, :payload => JSON.pretty_generate(json), :payload_type => "json", **kwargs)
  end

  def run(inputs: {}, userid: "system", zone: nil, role: "automate", object: nil, execution_context: {})
    require "floe"

    manager_ref = SecureRandom.uuid

    execution_context = execution_context.dup

    execution_context["Id"]                = manager_ref
    execution_context["_manageiq_api_url"] = MiqRegion.my_region.remote_ws_url
    execution_context["_manageiq_ui_url"]  = MiqRegion.my_region.remote_ui_url

    if object
      execution_context["_object_type"] = object.class.name
      execution_context["_object_id"]   = object.id
    end

    execution_context["_requester_userid"] = userid
    if User.current_userid == userid
      execution_context["_requester_email"] = User.current_user.email
    else
      current_user = User.find_by("userid" => userid)
      execution_context["_requester_email"] = current_user.email if current_user
    end

    context = Floe::Workflow::Context.new({"Execution" => execution_context}, :input => inputs.to_json)

    miq_task = instance = nil
    transaction do
      miq_task = MiqTask.create!(
        :name   => "Execute Workflow",
        :userid => userid
      )

      instance = children.create!(
        :manager       => manager,
        :manager_ref   => manager_ref,
        :type          => "#{manager.class}::WorkflowInstance",
        :name          => name,
        :run_by_userid => userid,
        :miq_task      => miq_task,
        :payload       => payload,
        :credentials   => credentials || {},
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
