require "manageiq/providers/workflows/engine"
require "manageiq/providers/workflows/version"

module ManageIQ
  module Providers
    module Workflows
      def self.seed
        # provider = ManageIQ::Providers::Workflows::Provider.in_my_region.first_or_initialize
        # provider.update!(
        #   :name => "Embedded Workflows",
        #   :zone => provider.zone || MiqServer.my_server.zone
        # )
        #
        # manager = provider.automation_manager
        manager = ManageIQ::Providers::Workflows::AutomationManager.in_my_region.first_or_initialize
        manager.update!(
          :name => "Embedded Workflows",
          :zone => MiqServer.my_server.zone # TODO: Do we even need zone?
        )
      end
    end
  end
end
