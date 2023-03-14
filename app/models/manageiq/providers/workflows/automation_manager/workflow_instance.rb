class ManageIQ::Providers::Workflows::AutomationManager::WorkflowInstance < WorkflowInstance
  def run_queue
    queue_opts = {
      :class_name  => self.class.name,
      :instance_id => id,
      :method_name => "run",
      :args        => [],
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

    case status
    when "running"
      miq_task.update_status(MiqTask::STATE_ACTIVE, MiqTask::STATUS_OK, "Workflow running") # TODO: Can we get the last state here?
    when "success"
      miq_task.update_status(MiqTask::STATE_FINISHED, MiqTask::STATUS_OK, "Workflow completed successfully")
    when "error"
      miq_task.update_status(MiqTask::STATE_FINISHED, MiqTask::STATUS_ERROR, "Workflow completed in failure") # TODO: Not sure if this should be MiqTask::STATUS_WARN instead?
    end
  end

  def run
    credentials = workflow.credentials&.transform_values do |val|
      ManageIQ::Password.try_decrypt(val)
    end

    wf = ManageIQ::Floe::Workflow.new(workflow.payload, context["global"], credentials)
    current_state = wf.states_by_name[context["current_state"]]

    input = output

    tick = Time.now.utc
    next_state, output = current_state.run!(input)
    tock = Time.now.utc

    context["current_state"] = next_state&.name
    context["states"] << {
      "name"   => current_state.name,
      "start"  => tick,
      "end"    => tock,
      "input"  => input,
      "output" => output
    }

    self.output = output
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
end
