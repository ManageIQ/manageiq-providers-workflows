class ManageIQ::Providers::Workflows::AutomationManager::Credential < ManageIQ::Providers::EmbeddedAutomationManager::Authentication
  def self.credential_type
    "workflows_credential_types"
  end
end
