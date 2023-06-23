class ManageIQ::Providers::Workflows::AutomationManager::ScmCredential < ManageIQ::Providers::Workflows::AutomationManager::Authentication
  include ManageIQ::Providers::EmbeddedAutomationManager::ScmCredentialMixin

  FRIENDLY_NAME = "Workflows SCM Credential".freeze
end
