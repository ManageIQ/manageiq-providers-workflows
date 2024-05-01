module ManageIQ
  module Providers
    module Workflows
      require "floe"

      class BuiltinRunnner < Floe::Runner
        SCHEME = "builtin"

        def run_async!(resource, params = {}, secrets = {}, context = {})
          scheme_prefix = "#{SCHEME}://"
          raise ArgumentError, "Invalid resource" unless resource&.start_with?(scheme_prefix)

          method = resource.sub(scheme_prefix, "")

          # TODO: prevent calling anything except the specifics methods, e.g. you shouldn't be able to call .to_s.
          #       Maybe make BuiltinMethods a BasicObject?
          BuiltinMethods.public_send(method, params)
        end

        def cleanup(_runner_context)
        end

        def wait(timeout: nil, events: %i[create update delete])
          # TODO: wait_for_task?
        end

        def status!(runner_context)
          if runner_context["miq_task_id"]
            miq_task = MiqTask.find(runner_context["miq_task_id"])
            return if miq_task.nil?

            runner_context["running"] = miq_task.state != MiqTask::STATE_FINISHED
            unless runner_context["running"]
              runner_context["success"] = miq_task.status == MiqTask::STATUS_OK
            end
          else
            runner_context["running"] = false
            runner_context["success"] = true
          end
        end

        def running?(runner_context)
          runner_context["running"]
        end

        def success?(runner_context)
          runner_context["success"]
        end

        def output(runner_context)
          runner_context["output"]
        end
      end
    end
  end
end

Floe::Runner.register_scheme(ManageIQ::Providers::Workflows::BuiltinRunnner::SCHEME, ManageIQ::Providers::Workflows::BuiltinRunnner.new)
