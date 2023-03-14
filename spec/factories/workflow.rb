FactoryBot.define do
  factory :workflows_automation_workflow, :class => "ManageIQ::Providers::Workflows::AutomationManager::Workflow", :parent => :workflow
end
