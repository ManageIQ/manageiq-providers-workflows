require_relative "builtin_result_mixin"

module ManageIQ
  module Providers
    module Workflows
      class BuiltinMethods < BasicObject
        extend BuiltinResultMixin

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

          # ensure we are in a provisioning request
          return error!({}, :cause => "Calling provision_execute on non-provisioning request: [#{object_type}]") unless object_type == "ServiceTemplateProvisionTask"
          return error!({}, :cause => "Missing MiqRequestTask id") if object_id.nil?

          miq_request_task = ::MiqRequestTask.find_by(:id => object_id.to_i)
          return error!({}, :cause => "Unable to find MiqReqeustTask id: [#{object_id}]") if miq_request_task.nil?

          miq_request_task.execute

          {"miq_request_task_id" => miq_request_task.id}
        end

        private_class_method def self.provision_execute_status!(runner_context)
          miq_request_task_status!(runner_context)
        end

        # general methods

        private_class_method def self.miq_task_status!(runner_context)
          miq_task = ::MiqTask.find_by(:id => runner_context["miq_task_id"])
          return error!(runner_context, :cause => "Unable to find MiqTask id: [#{runner_context["miq_task_id"]}]") if miq_task.nil?

          runner_context["running"] = miq_task.state != ::MiqTask::STATE_FINISHED

          unless runner_context["running"]
            runner_context["success"] = miq_task.status == ::MiqTask::STATUS_OK
            if runner_context["success"]
              runner_context["output"] = miq_task.message
            else
              error!(runner_context, :cause => miq_task.message)
            end
          end

          runner_context
        end

        private_class_method def self.miq_request_task_status!(runner_context)
          miq_request_task = ::MiqRequestTask.find_by(:id => runner_context["miq_request_task_id"])

          case miq_request_task&.statemachine_task_status
          when nil
            reason = "Unable to find MiqRequestTask id: [#{runner_context["miq_request_task_id"]}]"
            error!(runner_context, :cause => reason)
          when "error"
            reason = request_task.message&.sub(/^Error: /, "")
            error!(runner_context, :cause => reason)
          when "retry"
            runner_context["running"] = true
            runner_context
          when "ok"
            success!(runner_context, :output => {"Result" => "provisioned"})
          end
        end
      end
    end
  end
end
