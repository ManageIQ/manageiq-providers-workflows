module ManageIQ
  module Providers
    module Workflows
      require "floe"

      class BuiltinRunner < Floe::BuiltinRunner::Runner
        SCHEME = "manageiq".freeze
        SCHEME_PREFIX = "#{SCHEME}://".freeze

        def run_async!(resource, params, secrets, context)
          raise ArgumentError, "Invalid resource" unless resource&.start_with?(SCHEME_PREFIX)

          method_name = resource.sub(SCHEME_PREFIX, "")

          begin
            runner_context = {"method" => method_name}
            method_result = BuiltinMethods.public_send(method_name, params, secrets, context)
            method_result.merge(runner_context)
          rescue NoMethodError
            Floe::BuiltinRunner.error!(runner_context, :cause => "undefined method [#{method_name}]")
          rescue => err
            Floe::BuiltinRunner.error!(runner_context, :cause => err.to_s)
          ensure
            cleanup(runner_context)
          end
        end
      end
    end
  end
end

Floe::Runner.register_scheme(ManageIQ::Providers::Workflows::BuiltinRunner::SCHEME, ManageIQ::Providers::Workflows::BuiltinRunner.new)
