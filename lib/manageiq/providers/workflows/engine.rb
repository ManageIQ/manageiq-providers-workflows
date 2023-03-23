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
      end
    end
  end
end
