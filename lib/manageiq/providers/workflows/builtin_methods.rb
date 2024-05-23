module ManageIQ
  module Providers
    module Workflows
      class BuiltinMethods < BasicObject
        def self.email(params = {}, _secrets = {}, _context = {})
          options = params.slice("To", "From", "Subject", "Cc", "Bcc", "Body", "Attachment").transform_keys { |k| k.downcase.to_sym }

          miq_task = ::GenericMailer.deliver_task(:generic_notification, options)

          {"miq_task_id" => miq_task.id}
        end

        private_class_method def self.email_status!(runner_context)
          miq_task_status!(runner_context)
        end

        def self.provision_execute(_params = {}, _secrets = {}, context = {})
          object_type, object_id = context.execution.values_at("_object_type", "_object_id")
          return BuiltinRunnner.error!({}, :cause => "Missing MiqRequestTask type") if object_type.nil?
          return BuiltinRunnner.error!({}, :cause => "Missing MiqRequestTask id")   if object_id.nil?

          miq_request_task = ::MiqRequestTask.find_by(:id => object_id.to_i)
          return BuiltinRunnner.error!({}, :cause => "Unable to find MiqReqeustTask id: [#{object_id}]")                        if miq_request_task.nil?
          return BuiltinRunnner.error!({}, :cause => "Calling provision_execute on non-provisioning request: [#{object_type}]") unless miq_request_task.class < ::MiqProvision

          new_options = context.input.symbolize_keys.slice(*miq_request_task.options.keys)
          miq_request_task.options_will_change!
          miq_request_task.options.merge!(new_options)
          miq_request_task.save!
          miq_request_task.execute_queue

          {"miq_request_task_id" => miq_request_task.id}
        end

        private_class_method def self.provision_execute_status!(runner_context)
          miq_request_task_status!(runner_context)
        end

        # general methods

        private_class_method def self.miq_task_status!(runner_context)
          miq_task = ::MiqTask.find_by(:id => runner_context["miq_task_id"])
          return BuiltinRunnner.error!(runner_context, :cause => "Unable to find MiqTask id: [#{runner_context["miq_task_id"]}]") if miq_task.nil?

          runner_context["running"] = miq_task.state != ::MiqTask::STATE_FINISHED

          unless runner_context["running"]
            runner_context["success"] = miq_task.status == ::MiqTask::STATUS_OK
            if runner_context["success"]
              runner_context["output"] = miq_task.message
            else
              BuiltinRunnner.error!(runner_context, :cause => miq_task.message)
            end
          end

          runner_context
        end

        private_class_method def self.miq_request_task_status!(runner_context)
          miq_request_task = ::MiqRequestTask.find_by(:id => runner_context["miq_request_task_id"])

          case miq_request_task&.statemachine_task_status
          when nil
            reason = "Unable to find MiqRequestTask id: [#{runner_context["miq_request_task_id"]}]"
            BuiltinRunnner.error!(runner_context, :cause => reason)
          when "error"
            reason = miq_request_task.message&.sub(/^Error: /, "")
            BuiltinRunnner.error!(runner_context, :cause => reason)
          when "retry"
            runner_context["running"] = true
            runner_context
          when "ok"
            BuiltinRunnner.success!(runner_context, :output => {"Result" => "provisioned"})
          end
        end
      end
    end
  end
end
