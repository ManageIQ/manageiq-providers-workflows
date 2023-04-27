class ManageIQ::Providers::Workflows::AutomationManager < ManageIQ::Providers::EmbeddedAutomationManager
  require_nested :ConfigurationScriptSource
  require_nested :Workflow
  require_nested :WorkflowInstance

  def self.hostname_required?
    # TODO: ExtManagementSystem is validating this
    false
  end

  def self.ems_type
    @ems_type ||= "workflows".freeze
  end

  def self.description
    @description ||= "Embedded Workflows".freeze
  end
end
