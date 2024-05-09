module ManageIQ
  module Providers
    module Workflows
      module BuiltinResultMixin
        def error!(runner_context = {}, cause:, error: "States.TaskFailed")
          runner_context.merge!(
            "running" => false, "success" => false, "output" => {"Error" => error, "Cause" => cause}
          )
        end

        def success!(runner_context = {}, output:)
          runner_context.merge!(
            "running" => false, "success" => true, "output" => output
          )
        end
      end
    end
  end
end
