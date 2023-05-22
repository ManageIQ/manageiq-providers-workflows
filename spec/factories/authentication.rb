FactoryBot.define do
  factory :workflows_automation_authentication,
          :parent => :embedded_automation_manager_authentication,
          :class  => "ManageIQ::Providers::Workflows::AutomationManager::Authentication"
end
