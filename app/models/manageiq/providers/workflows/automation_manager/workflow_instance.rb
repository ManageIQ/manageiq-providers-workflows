class ManageIQ::Providers::Workflows::AutomationManager::WorkflowInstance < ManageIQ::Providers::EmbeddedAutomationManager::ConfigurationScript
  def run_queue(zone: nil, role: "automate", object: nil, deliver_on: nil, server_guid: nil)
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
      :queue_name  => "automate",
      :role        => role,
      :zone        => zone,
      :args        => [args],
      :deliver_on  => deliver_on,
      :server_guid => server_guid
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

    creds = credentials&.to_h do |key, val|
      if key.end_with?(".$")
        credential_ref, credential_field = val.values_at("credential_ref", "credential_field")

        authentication = parent.authentications.find_by(:ems_ref => credential_ref)
        raise ActiveRecord::RecordNotFound, "Couldn't find Authentication" if authentication.nil?

        [key.chomp(".$"), authentication.send(credential_field)]
      else
        [key, val]
      end
    end

    wf = Floe::Workflow.new(payload, context, creds)
    wf.run_nonblock

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

    run_queue(:zone => zone, :role => role, :object => object, :deliver_on => 10.seconds.from_now.utc, :server_guid => MiqServer.my_server.guid) unless wf.end?
  end
end
