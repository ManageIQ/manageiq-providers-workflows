class ManageIQ::Providers::Workflows::AutomationManager::WorkflowInstance < WorkflowInstance
  def run_queue(args = {}, options = {})
    queue_opts = {
      :class_name  => self.class.name,
      :instance_id => id,
      :method_name => "run",
      :args        => [args, options],
    }.merge(options)

    if miq_task_id
      queue_opts[:miq_callback] = {
        :class_name  => self.class.name,
        :instance_id => id,
        :method_name => :queue_callback
      }
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

  def run(args = {}, options = {})
    object = args[:object_type]&.constantize&.find_by(:id => args[:object_id])
    object.before_ae_starts({}) if object&.respond_to?(:before_ae_starts)

    creds = credentials&.transform_values do |val|
      ManageIQ::Password.try_decrypt(val)
    end

    wf = Floe::Workflow.new(workflow_content, context["global"], creds)
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

    run_queue(args, options) if next_state.present?
  ensure
    if object&.respond_to?(:after_ae_delivery)
      ae_result =
        case status
        when "running" then "retry"
        when "success" then "ok"
        when "error"   then "error"
        end

      object.after_ae_delivery(ae_result)
    end
  end
end
