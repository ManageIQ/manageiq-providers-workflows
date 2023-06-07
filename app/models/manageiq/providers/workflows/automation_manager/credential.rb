class ManageIQ::Providers::Workflows::AutomationManager::Credential < ManageIQ::Providers::EmbeddedAutomationManager::Authentication
  validates :ems_ref, :presence => true, :uniqueness_when_changed => {:scope => [:tenant_id]},
            :format => {:with => /\A[\w\-]+\z/i, :message => N_("may contain only alphanumeric and _ - characters")}

  FRIENDLY_NAME = "Workflows Credential"

  def self.params_to_attributes(params)
    params
  end
end
