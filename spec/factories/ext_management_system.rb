FactoryBot.define do
  factory :ems_workflows_automation, :class => "ManageIQ::Providers::Workflows::AutomationManager", :parent => :embedded_automation_manager
end
