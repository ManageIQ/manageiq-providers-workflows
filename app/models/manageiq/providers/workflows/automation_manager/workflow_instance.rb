class ManageIQ::Providers::Workflows::AutomationManager::WorkflowInstance < WorkflowInstance
  def run_queue
    MiqQueue.put(
      :class_name  => self.class.name,
      :instance_id => id,
      :method_name => "run"
    )
  end

  def run
    state = ManageIQ::Floe::Workflow.new(workflow.payload, context["global"]).states_by_name[context["states"]["current_state"]]

    tick = Time.now.utc
    next_state, outputs = state.run!
    tock = Time.now.utc

    context["states"][state.name] << {"start" => tick, "end" => tock, "outputs" => outputs}
    context["states"]["current_state"] = next_state&.name

    self.status = if next_state.present?
                    "running"
                  elsif state.type == "Fail"
                    "error"
                  elsif state.type == "Success" || state.try(:end)
                    "success"
                  end

    save!

    run_queue
  end
end
