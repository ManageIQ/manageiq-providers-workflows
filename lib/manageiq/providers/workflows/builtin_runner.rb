module ManageIQ
  module Providers
    module Workflows
      class BuiltinRunnner < Floe::Runner
        SCHEME = "builtin"

        def run_async!(resource, env = {}, secrets = {})
          scheme_prefix = "#{SCHEME}://"
          raise ArgumentError, "Invalid resource" unless resource&.start_with?(scheme_prefix)

          method = resource.sub(scheme_prefix, "")

          # TODO: prevent calling anything except the specifics methods, e.g. you shouldn't be able to call .to_s.
          #       Maybe make BuiltinMethods a BasicObject?
          BuiltinMethods.public_send(method)
        end

        def cleanup(runner_context)
        end

        def wait(timeout: nil, events: %i[create update delete])
          # TODO: wait_for_task?
        end

        def status!(runner_context)
        end

        def running?(runner_context)
        end

        def success?(runner_context)
        end

        def output(runner_context)
        end
      end
    end
  end
end

Floe::Runner.register_scheme(ManageIQ::Providers::Worfklows::BuiltinRunnner::SCHEME, ManageIQ::Providers::Worfklows::BuiltinRunnner.new)
