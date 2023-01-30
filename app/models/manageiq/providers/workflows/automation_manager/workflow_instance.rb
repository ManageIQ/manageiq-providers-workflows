class ManageIQ::Providers::Workflows::AutomationManager::WorkflowInstance < WorkflowInstance
  def run_queue
    queue_opts = {
      :class_name   => self.class.name,
      :instance_id  => id,
      :method_name  => "run",
      :args         => [],
    }

    if miq_task_id
      queue_opts.merge!(
        # :miq_task_id  => miq_task_id, # TODO: This causes the state to move to active on each step - not sure why
        :miq_callback => {
          :class_name  => self.class.name,
          :instance_id => id,
          :method_name => :queue_callback
        }
      )
    end

    MiqQueue.put(queue_opts)
  end

  def queue_callback(state, message, _result)
    if state != MiqQueue::STATUS_OK
      miq_task.update_status(MiqTask::STATE_FINISHED, MiqTask::STATUS_ERROR, "Workflow failed: #{message}")
      return
    end

    case self.status
    when "running"
      miq_task.update_status(MiqTask::STATE_ACTIVE, MiqTask::STATUS_OK, "Workflow running") # TODO: Can we get the last state here?
    when "success"
      miq_task.update_status(MiqTask::STATE_FINISHED, MiqTask::STATUS_OK, "Workflow completed successfully")
    when "error"
      miq_task.update_status(MiqTask::STATE_FINISHED, MiqTask::STATUS_ERROR, "Workflow completed in failure") # TODO: Not sure if this should be MiqTask::STATUS_WARN instead?
    end
  end

  def run
    wf = ManageIQ::Floe::Workflow.new(workflow.payload, context["global"])
    current_state = wf.states_by_name[context["current_state"]]

    tick = Time.now.utc
    next_state, outputs = current_state.run!
    tock = Time.now.utc

    # HACK: Inject some values pretending that "NextState" wrote these values into the workspace
    fake_workflow_outputs(current_state)

    context["states"] << {"start" => tick, "end" => tock, "outputs" => outputs}
    context["current_state"] = next_state&.name

    self.status = if next_state.present?
                    "running"
                  elsif current_state.type == "Fail"
                    "error"
                  elsif current_state.type == "Succeed" || current_state.try(:end)
                    "success"
                  end

    save!

    run_queue if next_state.present?
  end

  def fake_workflow_outputs(state)
    case state.name
    when "IpamIps"
      context["global"]["values"] = {
        "192.168.1.1" => "IP Address 1 (192.168.1.1)",
        "192.168.1.2" => "IP Address 2 (192.168.1.2)",
        "192.168.1.3" => "IP Address 3 (192.168.1.3)"
      }
    end
  end
end
