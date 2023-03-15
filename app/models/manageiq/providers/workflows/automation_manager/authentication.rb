class ManageIQ::Providers::Workflows::AutomationManager::Authentication < ManageIQ::Providers::AutomationManager::Authentication
  validates :name, :presence => true, :uniqueness_when_changed => {:scope => [:tenant_id]}
end
