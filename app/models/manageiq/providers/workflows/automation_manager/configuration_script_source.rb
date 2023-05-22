class ManageIQ::Providers::Workflows::AutomationManager::ConfigurationScriptSource < ManageIQ::Providers::EmbeddedAutomationManager::ConfigurationScriptSource
  FRIENDLY_NAME = "Embedded Workflows Repository".freeze

  def self.display_name(number = 1)
    n_('Repository (Embedded Workflows)', 'Repositories (Embedded Workflows)', number)
  end

  def sync
    update!(:status => "running")

    transaction do
      current = configuration_script_payloads.index_by(&:name)

      git_repository.update_repo
      git_repository.with_worktree do |worktree|
        worktree.ref = scm_branch
        worktree.blob_list.each do |filename|
          next if filename.start_with?(".") || !filename.end_with?(".asl")

          payload = worktree.read_file(filename)
          found   = current.delete(filename) || self.class.module_parent::Workflow.new(:configuration_script_source_id => id)

          found.update!(:name => filename, :manager_id => manager_id, :payload => payload, :payload_type => "json")
        end
      end

      current.values.each(&:destroy)
      configuration_script_payloads.reload
    end

    update!(:status => "successful", :last_updated_on => Time.zone.now, :last_update_error => nil)
  rescue => error
    update!(:status => "error", :last_updated_on => Time.zone.now, :last_update_error => error)
    raise error
  end
end
