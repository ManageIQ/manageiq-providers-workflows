RSpec.describe ManageIQ::Providers::Workflows::AutomationManager::ConfigurationScriptSource do
  context "with a local repo" do
    let(:ems) { FactoryBot.create(:ems_workflows_automation) }
    let(:params) do
      {
        :name    => "hello_world",
        :scm_url => "file://#{local_repo}"
      }
    end

    let(:clone_dir)          { Dir.mktmpdir }
    let(:local_repo)         { File.join(clone_dir, "hello_world_local") }
    let(:repo_dir)           { Pathname.new(Dir.mktmpdir) }
    let(:repos)              { Dir.glob(File.join(repo_dir, "*")) }
    let(:repo_dir_structure) { %w[hello_world.asl] }

    before do
      FileUtils.mkdir_p(local_repo)

      repo = Spec::Support::FakeWorkflowsRepo.new(local_repo, repo_dir_structure)
      repo.generate
      repo.git_branch_create("other_branch")

      GitRepository
      stub_const("GitRepository::GIT_REPO_DIRECTORY", repo_dir)

      EvmSpecHelper.assign_embedded_ansible_role
    end

    # Clean up repo dir after each spec
    after do
      FileUtils.rm_rf(repo_dir)
      FileUtils.rm_rf(clone_dir)
    end

    def files_in_repository(git_repo_dir)
      repo = Rugged::Repository.new(git_repo_dir.to_s)
      repo.ref("HEAD").target.target.tree.find_all.pluck(:name)
    end

    describe ".create_in_provider" do
      context "with valid params" do
        it "creates a record and initializes a git repo" do
          result = described_class.create_in_provider(ems.id, params)

          expect(result).to be_an(described_class)
          expect(result.scm_type).to eq("git")
          expect(result.scm_branch).to eq("master")
          expect(result.status).to eq("successful")
          expect(result.last_updated_on).to be_an(Time)
          expect(result.last_update_error).to be_nil

          git_repo_dir = repo_dir.join(result.git_repository.id.to_s)
          expect(files_in_repository(git_repo_dir)).to eq ["hello_world.asl"]
        end

        # NOTE:  Second `.notify` stub below prevents `.sync` from getting fired
        it "sets the status to 'new' on create" do
          expect(described_class).to receive(:notify).with(any_args).and_call_original
          expect(described_class).to receive(:notify).with("syncing", any_args).and_return(true)

          result = described_class.create_in_provider(ems.id, params)

          expect(result).to be_an(described_class)
          expect(result.scm_type).to eq("git")
          expect(result.scm_branch).to eq("master")
          expect(result.status).to eq("new")
          expect(result.last_updated_on).to be_nil
          expect(result.last_update_error).to be_nil

          expect(repos).to be_empty
        end
      end

      context "with invalid params" do
        it "does not create a record and does not call git" do
          params[:name] = nil
          expect(AwesomeSpawn).to receive(:run!).never

          expect do
            described_class.create_in_provider ems.id, params
          end.to raise_error(ActiveRecord::RecordInvalid)

          expect(repos).to be_empty
        end
      end

      context "when there is a network error fetching the repo" do
        before do
          allow_any_instance_of(GitRepository).to receive(:with_worktree).and_raise(::Rugged::NetworkError)

          expect do
            described_class.create_in_provider(ems.id, params)
          end.to raise_error(::Rugged::NetworkError)
        end

        it "sets the status to 'error' if syncing has a network error" do
          result = described_class.last

          expect(result).to be_an(described_class)
          expect(result.scm_type).to eq("git")
          expect(result.scm_branch).to eq("master")
          expect(result.status).to eq("error")
          expect(result.last_updated_on).to be_an(Time)
          expect(result.last_update_error).to start_with("Rugged::NetworkError")

          expect(repos).to be_empty
        end

        it "clears last_update_error on re-sync" do
          result = described_class.last

          expect(result.status).to eq("error")
          expect(result.last_updated_on).to be_an(Time)
          expect(result.last_update_error).to start_with("Rugged::NetworkError")

          allow_any_instance_of(GitRepository).to receive(:with_worktree).and_call_original

          result.sync

          expect(result.status).to eq("successful")
          expect(result.last_update_error).to be_nil
        end
      end
    end

    describe ".create_in_provider_queue" do
      it "creates a task and queue item" do
        EvmSpecHelper.local_miq_server
        task_id = described_class.create_in_provider_queue(ems.id, params)
        expect(MiqTask.find(task_id)).to have_attributes(:name => "Creating #{described_class::FRIENDLY_NAME} (name=#{params[:name]})")
        expect(MiqQueue.first).to have_attributes(
          :args        => [ems.id, params],
          :class_name  => described_class.name,
          :method_name => "create_in_provider",
          :priority    => MiqQueue::HIGH_PRIORITY,
          :role        => nil,
          :zone        => nil
        )
      end
    end

    describe "#verify_ssl" do
      it "defaults to OpenSSL::SSL::VERIFY_NONE" do
        expect(subject.verify_ssl).to eq(OpenSSL::SSL::VERIFY_NONE)
      end

      it "can be updated to OpenSSL::SSL::VERIFY_PEER" do
        subject.verify_ssl = OpenSSL::SSL::VERIFY_PEER
        expect(subject.verify_ssl).to eq(OpenSSL::SSL::VERIFY_PEER)
      end

      context "with a created record" do
        subject             { described_class.last }
        let(:create_params) { params.merge(:verify_ssl => OpenSSL::SSL::VERIFY_PEER) }

        before do
          described_class.create_in_provider(ems.id, create_params)
        end

        it "pulls from the created record" do
          expect(subject.verify_ssl).to eq(OpenSSL::SSL::VERIFY_PEER)
        end

        it "pushes updates from the ConfigurationScriptSource to the GitRepository" do
          subject.update(:verify_ssl => OpenSSL::SSL::VERIFY_NONE)

          expect(described_class.last.verify_ssl).to eq(OpenSSL::SSL::VERIFY_NONE)
          expect(GitRepository.last.verify_ssl).to   eq(OpenSSL::SSL::VERIFY_NONE)
        end

        it "converts true/false values instead of integers" do
          subject.update(:verify_ssl => false)

          expect(described_class.last.verify_ssl).to eq(OpenSSL::SSL::VERIFY_NONE)
          expect(GitRepository.last.verify_ssl).to   eq(OpenSSL::SSL::VERIFY_NONE)

          subject.update(:verify_ssl => true)

          expect(described_class.last.verify_ssl).to eq(OpenSSL::SSL::VERIFY_PEER)
          expect(GitRepository.last.verify_ssl).to   eq(OpenSSL::SSL::VERIFY_PEER)
        end
      end
    end

    describe "#sync" do
      it "finds top level workflows" do
        record = build_record

        expect(record.configuration_script_payloads.pluck(:name)).to eq(%w[hello_world.asl])
      end

      it "saves the workflow payload" do
        record = build_record

        expect(record.configuration_script_payloads.first).to have_attributes(
          :name          => "hello_world.asl",
          :description   => "hello world",
          :payload       => a_string_including("\"Comment\": \"hello world\""),
          :payload_type  => "json",
          :payload_valid => true,
          :payload_error => nil
        )
      end

      context "with workflows with invalid json" do
        let(:repo_dir_structure) { %w[invalid_json.asl] }

        it "sets the payload_valid and payload_error attributes" do
          record = build_record
          expect(record.configuration_script_payloads.first).to have_attributes(
            :name          => "invalid_json.asl",
            :payload       => "{\"Invalid Json\"\n",
            :payload_type  => "json",
            :payload_valid => false,
            :payload_error => "unexpected token at '{\"Invalid Json\"\n'"
          )
        end
      end

      context "with workflows with missing states" do
        let(:repo_dir_structure) { %w[missing_states.asl] }

        it "sets the payload_valid and payload_error attributes" do
          record = build_record
          expect(record.configuration_script_payloads.first).to have_attributes(
            :name          => "missing_states.asl",
            :payload       => "{\"Comment\": \"Missing States\"}\n",
            :payload_type  => "json",
            :payload_valid => false,
            :payload_error => "Missing field \"States\""
          )
        end
      end

      context "with a nested dir" do
        let(:nested_repo) { File.join(clone_dir, "hello_world_nested") }

        let(:nested_repo_structure) do
          %w[
            project/hello_world.asl
          ]
        end

        it "finds all ASL workflows" do
          Spec::Support::FakeWorkflowsRepo.generate(nested_repo, nested_repo_structure)

          params[:scm_url] = "file://#{nested_repo}"
          record           = build_record

          expect(record.configuration_script_payloads.pluck(:name)).to eq(%w[project/hello_world.asl])
        end
      end

      context "with other files" do
        let(:well_documented_repo) { File.join(clone_dir, "well_documented") }
        let(:well_documented_repo_structure) do
          %w[
            hello_world.asl
            README.md
          ]
        end

        it "finds only ASL workflows" do
          Spec::Support::FakeWorkflowsRepo.generate(well_documented_repo, well_documented_repo_structure)

          params[:scm_url] = "file://#{well_documented_repo}"
          record           = build_record

          expect(record.configuration_script_payloads.pluck(:name)).to eq(%w[hello_world.asl])
        end
      end

      context "with hidden files" do
        let(:hide_and_seek_repo) { File.join(clone_dir, "hello_world_is_hiding") }

        let(:hide_and_seek_repo_structure) do
          %w[
            .aws/hello_world.asl
            .travis.yml
            hello_world.asl
          ]
        end

        it "finds only ASL workflows" do
          Spec::Support::FakeWorkflowsRepo.generate(hide_and_seek_repo, hide_and_seek_repo_structure)

          params[:scm_url] = "file://#{hide_and_seek_repo}"
          record           = build_record

          expect(record.configuration_script_payloads.pluck(:name)).to eq(%w[hello_world.asl])
        end
      end
    end

    describe "#update_in_provider" do
      let(:update_params) { {:scm_branch => "other_branch"} }

      context "with valid params" do
        it "updates the record and initializes a git repo" do
          record = build_record

          result = record.update_in_provider update_params

          expect(result).to be_an(described_class)
          expect(result.scm_branch).to eq("other_branch")

          git_repo_dir = repo_dir.join(result.git_repository.id.to_s)
          expect(files_in_repository(git_repo_dir)).to eq ["hello_world.asl"]
        end
      end

      context "with invalid params" do
        it "does not create a record and does not call git" do
          record                    = build_record
          update_params[:scm_type]  = 'svn' # oh dear god...

          expect(AwesomeSpawn).to receive(:run!).never

          expect do
            record.update_in_provider update_params
          end.to raise_error(ActiveRecord::RecordInvalid)
        end
      end

      context "when there is a network error fetching the repo" do
        before do
          record = build_record

          expect(record.git_repository).to receive(:update_repo).and_raise(::Rugged::NetworkError)

          expect do
            # described_class.last.update_in_provider update_params
            record.update_in_provider update_params
          end.to raise_error(::Rugged::NetworkError)
        end

        it "sets the status to 'error' if syncing has a network error" do
          result = described_class.last

          expect(result).to be_an(described_class)
          expect(result.scm_type).to eq("git")
          expect(result.scm_branch).to eq("other_branch")
          expect(result.status).to eq("error")
          expect(result.last_updated_on).to be_an(Time)
          expect(result.last_update_error).to start_with("Rugged::NetworkError")
        end

        it "clears last_update_error on re-sync" do
          result = described_class.last

          expect(result.status).to eq("error")
          expect(result.last_updated_on).to be_an(Time)
          expect(result.last_update_error).to start_with("Rugged::NetworkError")

          expect(result.git_repository).to receive(:update_repo).and_call_original

          result.sync

          expect(result.status).to eq("successful")
          expect(result.last_update_error).to be_nil
        end
      end
    end

    describe "#update_in_provider_queue" do
      it "creates a task and queue item" do
        record    = build_record
        task_id   = record.update_in_provider_queue({})
        task_name = "Updating #{described_class::FRIENDLY_NAME} (name=#{record.name})"

        expect(MiqTask.find(task_id)).to have_attributes(:name => task_name)
        expect(MiqQueue.first).to have_attributes(
          :instance_id => record.id,
          :args        => [{:task_id => task_id}],
          :class_name  => described_class.name,
          :method_name => "update_in_provider",
          :priority    => MiqQueue::HIGH_PRIORITY,
          :role        => nil,
          :zone        => nil
        )
      end
    end

    describe "#delete_in_provider" do
      it "deletes the record and removes the git dir" do
        record = build_record
        git_repo_dir = repo_dir.join(record.git_repository.id.to_s)

        record.delete_in_provider

        # Run most recent queue item (`GitRepository#broadcast_repo_dir_delete`)
        MiqQueue.get.deliver

        expect(record).to be_deleted

        expect(git_repo_dir).to_not exist
      end
    end

    describe "#delete_in_provider_queue" do
      it "creates a task and queue item" do
        record    = build_record
        task_id   = record.delete_in_provider_queue
        task_name = "Deleting #{described_class::FRIENDLY_NAME} (name=#{record.name})"

        expect(MiqTask.find(task_id)).to have_attributes(:name => task_name)
        expect(MiqQueue.first).to have_attributes(
          :instance_id => record.id,
          :args        => [],
          :class_name  => described_class.name,
          :method_name => "delete_in_provider",
          :priority    => MiqQueue::HIGH_PRIORITY,
          :role        => nil,
          :zone        => nil
        )
      end
    end

    def build_record
      described_class.create_in_provider ems.id, params
    end
  end

  describe "git_repository interaction" do
    let(:auth) { FactoryBot.create(:embedded_ansible_scm_credential) }
    let(:configuration_script_source) do
      described_class.create!(
        :name           => "foo",
        :scm_url        => "https://example.com/foo.git",
        :authentication => auth
      )
    end

    it "on .create" do
      configuration_script_source

      git_repository = GitRepository.first
      expect(git_repository.name).to eq "foo"
      expect(git_repository.url).to eq "https://example.com/foo.git"
      expect(git_repository.authentication).to eq auth

      expect { configuration_script_source.git_repository }.to_not make_database_queries
      expect(configuration_script_source.git_repository_id).to eq git_repository.id
    end

    it "on .new" do
      configuration_script_source = described_class.new(
        :name           => "foo",
        :scm_url        => "https://example.com/foo.git",
        :authentication => auth
      )

      expect(GitRepository.count).to eq 0

      attached_git_repository = configuration_script_source.git_repository

      git_repository = GitRepository.first
      expect(git_repository).to eq attached_git_repository
      expect(git_repository.name).to eq "foo"
      expect(git_repository.url).to eq "https://example.com/foo.git"
      expect(git_repository.authentication).to eq auth

      expect { configuration_script_source.git_repository }.to_not make_database_queries
      expect(configuration_script_source.git_repository_id).to eq git_repository.id
    end

    it "errors when scm_url is invalid" do
      expect do
        configuration_script_source.update!(:scm_url => "invalid url")
      end.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "syncs attributes down" do
      configuration_script_source.name = "bar"
      expect(configuration_script_source.git_repository.name).to eq "bar"

      configuration_script_source.scm_url = "https://example.com/bar.git"
      expect(configuration_script_source.git_repository.url).to eq "https://example.com/bar.git"

      configuration_script_source.authentication = nil
      expect(configuration_script_source.git_repository.authentication).to be_nil
    end

    it "persists attributes down" do
      configuration_script_source.update!(:name => "bar")
      expect(GitRepository.first.name).to eq "bar"

      configuration_script_source.update!(:scm_url => "https://example.com/bar.git")
      expect(GitRepository.first.url).to eq "https://example.com/bar.git"

      configuration_script_source.update!(:authentication => nil)
      expect(GitRepository.first.authentication).to be_nil
    end
  end
end
