class ManageIQ::Providers::Workflows::AutomationManager < ManageIQ::Providers::EmbeddedAutomationManager
  require_nested :Workflow
  require_nested :WorkflowInstance

  has_many :workflows, :class_name => "ManageIQ::Providers::Workflows::AutomationManager::Workflow",
           :dependent => :destroy, :foreign_key => :ems_id, :inverse_of => :ext_management_system
  has_many :workflow_instances, :class_name => "ManageIQ::Providers::Workflows::AutomationManager::WorkflowInstance",
           :dependent => :destroy, :foreign_key => :ems_id, :inverse_of => :ext_management_system

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
