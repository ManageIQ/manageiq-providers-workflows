module ManageIQ
  module Providers
    module Workflows
      class BuiltinMethods
        def self.email(params = {})
          options = {
            :to      => params["To"],
            :from    => params["From"],
            :subject => params["Subject"],
            :cc      => params["Cc"],
            :bcc     => params["Bcc"],
            :body    => params["Body"]
          }

          miq_task = GenericMailer.deliver_task(:generic_notification, options)

          {"miq_task_id" => miq_task.id}
        end
      end
    end
  end
end
