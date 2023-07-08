class ManageIQ::Providers::Workflows::AutomationManager::WorkflowCredential < ManageIQ::Providers::Workflows::AutomationManager::Credential
  validates :ems_ref, :presence => true, :uniqueness_when_changed => {:scope => [:tenant_id]},
            :format => {:with => /\A[\w\-]+\z/i, :message => N_("may contain only alphanumeric and _ - characters")}

  FRIENDLY_NAME = "Workflows Credential".freeze

  COMMON_ATTRIBUTES = [
    {
      :component  => 'text-field',
      :label      => N_('Reference'),
      :helperText => N_('Unique reference for this credential'),
      :name       => 'ems_ref',
      :id         => 'ems_ref',
      :isRequired => true,
      :validate   => [{:type => "required"}]
    },
    {
      :component  => 'text-field',
      :label      => N_('Username'),
      :helperText => N_('Username for this credential'),
      :name       => 'userid',
      :id         => 'userid'
    },
    {
      :component  => 'password-field',
      :label      => N_('Password'),
      :helperText => N_('Password for this credential'),
      :name       => 'password',
      :id         => 'password',
      :type       => 'password'
    },
    {
      :component      => 'password-field',
      :label          => N_('Private key'),
      :helperText     => N_('RSA or DSA private key to be used instead of password'),
      :componentClass => 'textarea',
      :name           => 'auth_key',
      :id             => 'auth_key',
      :type           => 'password'
    },
    {
      :component  => 'password-field',
      :label      => N_('Private key passphrase'),
      :helperText => N_('Passphrase to unlock SSH private key if encrypted'),
      :name       => 'auth_key_password',
      :id         => 'auth_key_password',
      :maxLength  => 1024,
      :type       => 'password'
    }
  ].freeze

  API_ATTRIBUTES = COMMON_ATTRIBUTES

  API_OPTIONS = {
    :label      => N_('Workflows'),
    :attributes => API_ATTRIBUTES
  }.freeze
end
