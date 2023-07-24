module ManageIQ
  module Providers
    module Workflows
      class Engine < ::Rails::Engine
        isolate_namespace ManageIQ::Providers::Workflows

        config.autoload_paths << root.join('lib').to_s

        initializer :append_secrets do |app|
          app.config.paths["config/secrets"] << root.join("config", "secrets.defaults.yml").to_s
          app.config.paths["config/secrets"] << root.join("config", "secrets.yml").to_s
        end

        def self.vmdb_plugin?
          true
        end

        def self.plugin_name
          _('Embedded Workflows Provider')
        end

        def self.init_loggers
          $workflows_log ||= Vmdb::Loggers.create_logger("workflows.log")

          require "floe"
          Floe.logger = $workflows_log
        end

        def self.apply_logger_config(config)
          Vmdb::Loggers.apply_config_value(config, $workflows_log, :level_workflows)
        end

        def self.seedable_classes
          %w[ManageIQ::Providers::Workflows]
        end

        def self.floe_docker_runner
          require "miq_environment"
          require "floe"

          if MiqEnvironment::Command.is_podified?
            host = ENV.fetch("KUBERNETES_SERVICE_HOST")
            port = ENV.fetch("KUBERNETES_SERVICE_PORT")

            Floe::Workflow::Runner::Kubernetes.new(
              "server"     => URI::HTTPS.build(:host => host, :port => port).to_s,
              "token_file" => "/run/secrets/kubernetes.io/serviceaccount/token",
              "ca_cert"    => "/run/secrets/kubernetes.io/serviceaccount/ca.crt"
            )
          elsif MiqEnvironment::Command.is_appliance? || MiqEnvironment::Command.supports_command?("podman")
            Floe::Workflow::Runner::Podman.new
          else
            Floe::Workflow::Runner::Docker.new
          end
        end
      end
    end
  end
end
