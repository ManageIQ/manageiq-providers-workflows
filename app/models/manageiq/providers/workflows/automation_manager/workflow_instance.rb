class ManageIQ::Providers::Workflows::AutomationManager::WorkflowInstance < WorkflowInstance
  def run_queue
    MiqQueue.put(
      :class_name  => self.class.name,
      :instance_id => id,
      :method_name => "run"
    )
  end

  def run
    wf = ManageIQ::Floe::Workflow.new(workflow.payload, context["global"])
    current_state = wf.states_by_name[context["current_state"]]

    tick = Time.now.utc
    next_state, outputs = current_state.run!
    tock = Time.now.utc

    context["states"] << {"start" => tick, "end" => tock, "outputs" => outputs}
    context["current_state"] = next_state&.name

    self.status = if next_state.present?
                    "running"
                  elsif current_state.type == "Fail"
                    "error"
                  elsif current_state.type == "Success" || current_state.try(:end)
                    "success"
                  end

    save!

    run_queue if next_state.present?
  end
end
