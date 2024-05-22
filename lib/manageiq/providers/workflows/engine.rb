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
          %w[
            ManageIQ::Providers::Workflows
            ManageIQ::Providers::Workflows::AutomationManager::ConfigurationScriptSource
          ]
        end

        def self.floe_runner_name
          if (runner_setting = Settings.ems.ems_workflows.runner.presence)
            runner_setting
          elsif MiqEnvironment::Command.is_podified?
            "kubernetes"
          elsif MiqEnvironment::Command.is_appliance? || MiqEnvironment::Command.supports_command?("podman")
            "podman"
          else
            "docker"
          end
        end

        def self.set_floe_runner
          require "miq_environment"
          require "floe"
          require "floe/container_runner"

          floe_runner_settings = Settings.ems.ems_workflows.runner_options

          case floe_runner_name
          when "kubernetes"
            host = ENV.fetch("KUBERNETES_SERVICE_HOST")
            port = ENV.fetch("KUBERNETES_SERVICE_PORT")

            options = {
              "server"               => URI::HTTPS.build(:host => host, :port => port).to_s,
              "token_file"           => "/run/secrets/kubernetes.io/serviceaccount/token",
              "ca_cert"              => "/run/secrets/kubernetes.io/serviceaccount/ca.crt",
              "namespace"            => File.read("/run/secrets/kubernetes.io/serviceaccount/namespace"),
              "task_service_account" => ENV.fetch("AUTOMATION_JOB_SERVICE_ACCOUNT", nil)
            }.merge(floe_runner_settings.kubernetes)

            Floe::ContainerRunner.set_runner("kubernetes", options)
          when "podman"
            options = {}
            options["root"] = Rails.root.join("data/containers/storage").to_s if Rails.env.production?
            options.merge!(floe_runner_settings.podman)

            Floe::ContainerRunner.set_runner("podman", options)
          when "docker"
            options = floe_runner_settings.docker.to_hash

            Floe::ContainerRunner.set_runner("docker", options)
          else
            raise "Unknown runner: #{floe_runner_name}. expecting [kubernetes, podman, docker]"
          end
        end
      end
    end
  end
end
