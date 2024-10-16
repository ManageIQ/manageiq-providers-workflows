FactoryBot.define do
  factory :workflows_automation_workflow_instance, :class => "ManageIQ::Providers::Workflows::AutomationManager::Workflow_instance" do
    status { "pending" }
    manager_ref { SecureRandom.uuid }
  end
end
