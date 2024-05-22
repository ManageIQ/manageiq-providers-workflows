module ManageIQ
  module Providers
    module Workflows
      require "floe"

      class BuiltinRunnner < Floe::Runner
        SCHEME = "builtin".freeze
        SCHEME_PREFIX = "#{SCHEME}://".freeze

        class << self
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

        def run_async!(resource, params = {}, secrets = {}, context = {})
          raise ArgumentError, "Invalid resource" unless resource&.start_with?(SCHEME_PREFIX)

          method_name = resource.sub(SCHEME_PREFIX, "")

          begin
            runner_context = {"method" => method_name}
            method_result = BuiltinMethods.public_send(method_name, params, secrets, context)
            method_result.merge(runner_context)
          rescue NoMethodError
            self.class.error!(runner_context, :cause => "undefined method [#{method_name}]")
          rescue => err
            self.class.error!(runner_context, :cause => err.to_s)
          ensure
            cleanup(runner_context)
          end
        end

        def cleanup(runner_context)
          method_name = runner_context["method"]
          raise ArgumentError if method_name.nil?

          cleanup_method = "#{method_name}_cleanup"
          return unless BuiltinMethods.respond_to?(cleanup_method, true)

          BuiltinMethods.send(cleanup_method, runner_context)
        end

        def status!(runner_context)
          method_name = runner_context["method"]
          raise ArgumentError if method_name.nil?
          return if runner_context["running"] == false

          BuiltinMethods.send("#{method_name}_status!", runner_context)
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
