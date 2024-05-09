require_relative "builtin_result_mixin"

module ManageIQ
  module Providers
    module Workflows
      require "floe"

      class BuiltinRunnner < Floe::Runner
        extend BuiltinResultMixin

        SCHEME = "builtin".freeze
        SCHEME_PREFIX = "#{SCHEME}://".freeze

        def run_async!(resource, params = {}, secrets = {}, context = {})
          raise ArgumentError, "Invalid resource" unless resource&.start_with?(SCHEME_PREFIX)

          method_name = resource.sub(SCHEME_PREFIX, "")

          runner_context = {"method" => method_name}
          method_result = BuiltinMethods.public_send(method_name, params, secrets, context)
          method_result.merge(runner_context)
        rescue => err
          cleanup(runner_context)
          error!(runner_context, :cause => err.to_s)
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
