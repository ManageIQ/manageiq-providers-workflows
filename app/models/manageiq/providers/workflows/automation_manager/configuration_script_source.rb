class ManageIQ::Providers::Workflows::AutomationManager::ConfigurationScriptSource < ManageIQ::Providers::EmbeddedAutomationManager::ConfigurationScriptSource
  FRIENDLY_NAME     = "Embedded Workflows Repository".freeze
  BUILTIN_REPO_NAME = "ManageIQ Built-in Workflows".freeze

  supports :update do
    _("Cannot update the built-in repository") if name == BUILTIN_REPO_NAME
  end
  supports :delete do
    _("Cannot delete the built-in repository") if name == BUILTIN_REPO_NAME
  end

  def self.display_name(number = 1)
    n_('Repository (Embedded Workflows)', 'Repositories (Embedded Workflows)', number)
  end

  def self.seed
    manager = ManageIQ::Providers::Workflows::AutomationManager.in_my_region.first
    return if manager.nil?

    manager.configuration_script_sources
           .find_or_create_by!(:type => name, :name => BUILTIN_REPO_NAME)
           .sync
  end

  def sync
    update!(:status => "running")

    transaction do
      to_delete = configuration_script_payloads.index_by(&:name)

      if git_repository.present?
        sync_from_git_repository(to_delete)
      else
        sync_from_content(to_delete)
      end

      to_delete.each_value(&:destroy)
      configuration_script_payloads.reload
    end

    update!(:status => "successful", :last_updated_on => Time.zone.now, :last_update_error => nil)
  rescue => error
    update!(:status => "error", :last_updated_on => Time.zone.now, :last_update_error => error)
    raise error
  end

  private

  def sync_from_git_repository(to_delete)
    git_repository.update_repo
    git_repository.with_worktree do |worktree|
      worktree.ref = scm_branch
      worktree.blob_list.each do |filename|
        next if filename.start_with?(".") || !filename.end_with?(".asl")

        payload  = worktree.read_file(filename)
        workflow = create_workflow_from_payload(filename, payload, fail_on_invalid_workflow: false)

        to_delete.delete(workflow.name) if workflow
      end
    end
  end

  def sync_from_content(to_delete)
    Vmdb::Plugins.embedded_workflows_content.each do |engine, workflow_paths|
      base_dir = engine.root.join("content", "workflows")
      workflow_paths.each do |filename|
        workflow_name = filename.relative_path_from(base_dir).to_s
        payload       = File.read(filename)
        workflow      = create_workflow_from_payload(workflow_name, payload, fail_on_invalid_workflow: true)

        to_delete.delete(workflow.name) if workflow
      end
    end
  end

  def create_workflow_from_payload(name, payload, fail_on_invalid_workflow:)
    floe_workflow, payload_error =
      begin
        Floe::Workflow.new(payload)
      rescue Floe::InvalidWorkflowError, NotImplementedError => err
        _log.warn("Invalid ASL file [#{name}]: #{err}")
        raise if fail_on_invalid_workflow

        [nil, err.message]
      end

    description = floe_workflow&.comment

    configuration_script_payloads.find_or_initialize_by(:name => name).tap do |wf|
      wf.update!(
        :name          => name,
        :description   => description,
        :manager_id    => manager_id,
        :type          => self.class.module_parent::Workflow.name,
        :payload       => payload,
        :payload_type  => "json",
        :payload_valid => !!floe_workflow,
        :payload_error => payload_error
      )
    end
  end
end
