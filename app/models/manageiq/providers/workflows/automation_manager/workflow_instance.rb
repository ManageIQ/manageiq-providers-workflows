class ManageIQ::Providers::Workflows::AutomationManager::WorkflowInstance < ManageIQ::Providers::EmbeddedAutomationManager::ConfigurationScript
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
    creds = credentials&.transform_values do |val|
      if val.start_with?("$.")
        name, field = val.match(/^\$\.(?<name>.+)\.(?<field>.+)$/).named_captures.values_at("name", "field")

        authentication = Rbac.filtered_object(manager.authentications.find_by!(:name => name), :userid => run_by_userid, :miq_group_id => miq_group_id)
        raise ActiveRecord::RecordNotFound, "Couldn't find Authentication" if authentication.nil?

        authentication.send(field)
      else
        ManageIQ::Password.try_decrypt(val)
      end
    end

    wf = Floe::Workflow.new(payload, context["global"], creds)
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
