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
          # ensure we are in a provisioning request
          unless context.execution["_object_type"] == "ServiceTemplateProvisionTask"
            return BuiltinRunner.error!(runner_context, :cause => "Calling provision_execute on non-provisioning request: [#{runner_context["_object_type"]}]")
          end

          request_task_id = context.execution["_object_id"]&.to_i
          ::MiqRequestTask.find(request_task_id)&.execute

          {"miq_request_task_id" => request_task_id}
        end

        private_class_method def self.provision_execute_status!(runner_context)
          miq_request_task_status!(runner_context)
        end

        # general methods

        private_class_method def self.miq_task_status!(runner_context)
          miq_task = ::MiqTask.find_by(:id => runner_context["miq_task_id"])
          return BuiltinRunner.error!(runner_context, :cause => "Unable to find MiqTask id: [#{runner_context["miq_task_id"]}]") if miq_task.nil?

          runner_context["running"] = miq_task.state != ::MiqTask::STATE_FINISHED

          unless runner_context["running"]
            runner_context["success"] = miq_task.status == ::MiqTask::STATUS_OK
            if runner_context["success"]
              runner_context["output"] = miq_task.message
            else
              BuiltinRunner.error!(runner_context, :cause => miq_task.message)
            end
          end

          runner_context
        end

        private_class_method def self.miq_request_task_status!(runner_context)
          miq_request_task = ::MiqRequestTask.find_by(:id => runner_context["miq_request_task_id"])

          case miq_request_task&.statemachine_task_status
          when nil
            reason = "Unable to find MiqRequestTask id: [#{runner_context["miq_request_task_id"]}]"
            BuiltinRunner.error!(runner_context, :cause => reason)
          when "error"
            reason = request_task.message&.sub(/^Error: /, "")
            BuiltinRunner.error!(runner_context, :cause => reason)
          when "retry"
            runner_context["running"] = true
            runner_context
          when "ok"
            BuiltinRunner.success!(runner_context, :output => {"Result" => "provisioned"})
          end
        end
      end
    end
  end
end
