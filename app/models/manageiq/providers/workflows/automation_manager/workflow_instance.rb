class ManageIQ::Providers::Workflows::AutomationManager::WorkflowInstance < ManageIQ::Providers::EmbeddedAutomationManager::ConfigurationScript
  def run_queue(zone: nil, role: "automate", object: nil)
    raise _("run_queue is not enabled") unless Settings.prototype.ems_workflows.enabled

    args = {:zone => zone, :role => role}
    if object
      args[:object_type] = object.class.name
      args[:object_id]   = object.id
    end

    queue_opts = {
      :class_name  => self.class.name,
      :instance_id => id,
      :method_name => "run",
      :role        => role,
      :zone        => zone,
      :args        => [args],
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

  def run(args = {})
    raise _("run is not enabled") unless Settings.prototype.ems_workflows.enabled

    zone, role, object_type, object_id = args.values_at(:zone, :role, :object_type, :object_id)

    object = object_type.constantize.find_by(:id => object_id) if object_type && object_id
    object.before_ae_starts({}) if object.present? && object.respond_to?(:before_ae_starts)

    creds = credentials&.transform_values do |val|
      if val.start_with?("$.")
        ems_ref, field = val.match(/^\$\.(?<ems_ref>.+)\.(?<field>.+)$/).named_captures.values_at("ems_ref", "field")

        authentication = parent.authentications.find_by(:ems_ref => ems_ref)
        raise ActiveRecord::RecordNotFound, "Couldn't find Authentication" if authentication.nil?

        authentication.send(field)
      else
        val
      end
    end

    wf = Floe::Workflow.new(payload, context, creds)
    wf.step

    update!(:context => wf.context.to_h, :status => wf.status, :output => wf.output)

    if object.present? && object.respond_to?(:after_ae_delivery)
      ae_result =
        case status
        when "running"
          "retry"
        when "success"
          "ok"
        else
          status
        end

      object.after_ae_delivery(ae_result)
    end

    run_queue(:zone => zone, :role => role, :object => object) unless wf.end?
  end
end
