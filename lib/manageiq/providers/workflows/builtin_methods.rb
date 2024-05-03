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
          miq_task = ::MiqTask.find(runner_context["miq_task_id"])
          return if miq_task.nil?

          runner_context["running"] = miq_task.state != ::MiqTask::STATE_FINISHED
          runner_context["success"] = miq_task.status == ::MiqTask::STATUS_OK unless runner_context["running"]
          runner_context
        end

        private_class_method def self.email_cleanup(*)
        end
      end
    end
  end
end
