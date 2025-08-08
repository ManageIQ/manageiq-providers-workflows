RSpec.describe ManageIQ::Providers::Workflows::BuiltinMethods do
  require "floe"

  let(:ctx) { Floe::Workflow::Context.new }
  let(:secrets) { {} }

  describe ".http" do
    let(:faraday_stub) { double("Faraday::Connection") }

    before do
      require "faraday"
      allow(Faraday).to receive(:new).and_return(faraday_stub)
    end

    context "GET" do
      it "with a missing Method parameter" do
        runner_context = described_class.http({"Url" => "http://localhost"}, secrets, ctx)
        expect(runner_context)
          .to include(
            "running" => false,
            "success" => false,
            "output"  => failed_task_status("Missing Parameter: Method")
          )
      end

      it "with a missing Url parameter" do
        runner_context = described_class.http({"Method" => "GET"}, secrets, ctx)
        expect(runner_context)
          .to include(
            "running" => false,
            "success" => false,
            "output"  => failed_task_status("Missing Parameter: Url")
          )
      end

      it "with an invalid Method parameter" do
        runner_context = described_class.http({"Method" => "Fetch", "Url" => "http://localhost"}, secrets, ctx)
        expect(runner_context)
          .to include(
            "running" => false,
            "success" => false,
            "output"  => failed_task_status("Invalid Parameter: Method: [Fetch], must be GET, POST, PUT, DELETE, HEAD, PATCH, OPTIONS, or TRACE")
          )
      end

      it "performs the get" do
        expect(faraday_stub).to receive(:get).and_return(Faraday::Response.new(:status => 200, :body => "{}"))

        params = {"Method" => "GET", "Url" => "http://localhost"}
        runner_context = described_class.http(params, secrets, ctx)
        expect(runner_context)
          .to include(
            "running" => false,
            "success" => true,
            "output"  => {"Body" => "{}", "Headers" => nil, "Status" => 200}
          )
      end

      it "with query parameters" do
        expect(Faraday)
          .to receive(:new)
          .with(hash_including(:params => {"username" => "my-user"}))
          .and_return(faraday_stub)
        expect(faraday_stub).to receive(:get).and_return(Faraday::Response.new(:status => 200, :body => "{}"))

        params = {"Method" => "GET", "Url" => "http://localhost", "QueryParameters" => {"username" => "my-user"}}
        runner_context = described_class.http(params, secrets, ctx)
        expect(runner_context)
          .to include(
            "running" => false,
            "success" => true,
            "output"  => {"Body" => "{}", "Headers" => nil, "Status" => 200}
          )
      end

      it "with ssl parameters" do
        expect(Faraday)
          .to receive(:new)
          .with(hash_including(:ssl => {"verify" => true}))
          .and_return(faraday_stub)

        expect(faraday_stub).to receive(:get).and_return(Faraday::Response.new(:status => 200, :body => "{}"))

        params = {"Method" => "GET", "Url" => "http://localhost", "Ssl" => {"Verify" => true}}
        runner_context = described_class.http(params, secrets, ctx)
        expect(runner_context)
          .to include(
            "running" => false,
            "success" => true,
            "output"  => {"Body" => "{}", "Headers" => nil, "Status" => 200}
          )
      end

      it "with proxy options" do
        expect(Faraday)
          .to receive(:new)
          .with(hash_including(:proxy => {"uri" => "https://proxy:123", "user" => "user", "password" => "password"}))
          .and_return(faraday_stub)

        expect(faraday_stub).to receive(:get).and_return(Faraday::Response.new(:status => 200, :body => "{}"))

        params = {"Method" => "GET", "Url" => "http://localhost", "Proxy" => {"Uri" => "https://proxy:123", "User" => "user", "Password" => "password"}}
        runner_context = described_class.http(params, secrets, ctx)
        expect(runner_context)
          .to include(
            "running" => false,
            "success" => true,
            "output"  => {"Body" => "{}", "Headers" => nil, "Status" => 200}
          )
      end

      it "with request options" do
        expect(Faraday)
          .to receive(:new)
          .with(hash_including(:request => {"timeout" => 30, "read_timeout" => 10, "open_timeout" => 20, "write_timeout" => 10}))
          .and_return(faraday_stub)

        expect(faraday_stub).to receive(:get).and_return(Faraday::Response.new(:status => 200, :body => "{}"))

        params = {"Method" => "GET", "Url" => "http://localhost", "Options" => {"Timeout" => 30, "ReadTimeout" => 10, "OpenTimeout" => 20, "WriteTimeout" => 10}}
        runner_context = described_class.http(params, secrets, ctx)
        expect(runner_context)
          .to include(
            "running" => false,
            "success" => true,
            "output"  => {"Body" => "{}", "Headers" => nil, "Status" => 200}
          )
      end
    end

    context "POST" do
      it "performs the post" do
        expect(faraday_stub).to receive(:post).and_return(Faraday::Response.new(:status => 200, :body => "{}"))

        params = {"Method" => "POST", "Url" => "http://localhost", "Body" => {"foo" => "bar"}, "Headers" => {"Content-Type" => "application/json"}}
        runner_context = described_class.http(params, secrets, ctx)
        expect(runner_context)
          .to include(
            "running" => false,
            "success" => true,
            "output"  => {"Body" => "{}", "Headers" => nil, "Status" => 200}
          )
      end
    end
  end

  describe ".email" do
    let(:params) { {"To" => "foo@bar.com", "From" => "baz@bar.com"} }

    context "with no notifier" do
      it "fails emailing" do
        runner_context = described_class.email(params, secrets, ctx)
        expect(runner_context).to have_key("miq_task_id")
        expect(MiqTask.find_by(:id => runner_context["miq_task_id"])).to have_attributes(:state => "Finished", :status => "Error")
      end
    end

    context "with notifier" do
      let(:params) { {"To" => "foo@bar.com", "From" => "baz@bar.com"} }

      before do
        allow(MiqRegion.my_region).to receive(:role_assigned?).with('notifier').and_return(true)
        zone = FactoryBot.create(:zone)
        allow(MiqServer).to receive(:my_zone).and_return(zone.name)
      end

      it "defaults from and queues message" do
        stub_settings_merge(:smtp => {:from => "baz@system.com"})

        runner_context = described_class.email({"To" => "foo@bar.com"}, secrets, ctx)

        expect(task_id = runner_context["miq_task_id"]).not_to be_nil
        expect(MiqTask.find_by(:id => task_id)).to have_attributes(:state => "Queued", :status => "Ok")
        expected_attributes = {
          :class_name => "GenericMailer",
          :args       => [:generic_notification, {:to => "foo@bar.com", :from => "baz@system.com"}]
        }
        expect(MiqQueue.find_by(:miq_task_id => task_id)).to have_attributes(expected_attributes)
      end
    end
  end

  describe ".embedded_ansible" do
    let(:repo)     { FactoryBot.create(:embedded_ansible_configuration_script_source) }
    let(:playbook) { FactoryBot.create(:embedded_playbook, :configuration_script_source => repo) }
    before         { EvmSpecHelper.local_miq_server }

    context "with a missing repository" do
      it "returns an error that it couldn't find the repository" do
        params = {"RepositoryUrl" => "https://github.com/missing_repo.git", "RepositoryBranch" => "feature1"}
        expect(described_class.embedded_ansible(params, secrets, ctx))
          .to include(
            "running" => false,
            "success" => false,
            "output"  => failed_task_status("Unable to find Repository: URL: [https://github.com/missing_repo.git] Branch: [feature1]")
          )
      end
    end

    context "with a missing playbook" do
      it "returns an error that it couldn't find the playbook" do
        params = {"RepositoryUrl" => repo.scm_url, "RepositoryBranch" => repo.scm_branch, "PlaybookName" => "missing"}
        expect(described_class.embedded_ansible(params, secrets, ctx))
          .to include(
            "running" => false,
            "success" => false,
            "output"  => failed_task_status("Unable to find Playbook: Name: [missing] Repository: [#{repo.name}]")
          )
      end
    end

    context "with a non-embedded_ansible configuration_script_payload" do
      let(:workflow) { FactoryBot.create(:workflows_automation_workflow, :configuration_script_source => repo) }

      it "return an error" do
        params = {"RepositoryUrl" => repo.scm_url, "RepositoryBranch" => repo.scm_branch, "PlaybookName" => workflow.name}
        expect(described_class.embedded_ansible(params, secrets, ctx))
          .to include(
            "running" => false,
            "success" => false,
            "output"  => failed_task_status("Invalid playbook: ID: [#{workflow.id}] Type: [#{workflow.type}]")
          )
      end
    end

    context "with a PlaybookId" do
      it "calls playbook run" do
        params = {"PlaybookId" => playbook.id}
        expect(described_class.embedded_ansible(params, secrets, ctx)).to include("miq_task_id" => a_kind_of(Integer))
        expect(MiqQueue.first).to have_attributes(:class_name => "ManageIQ::Providers::AnsiblePlaybookWorkflow", :method_name => "signal")
      end
    end

    context "with a Repository/PlaybookName" do
      it "calls playbook run" do
        params = {"RepositoryUrl" => repo.scm_url, "RepositoryBranch" => repo.scm_branch, "PlaybookName" => playbook.name}
        expect(described_class.embedded_ansible(params, secrets, ctx)).to include("miq_task_id" => a_kind_of(Integer))
        expect(MiqQueue.first).to have_attributes(:class_name => "ManageIQ::Providers::AnsiblePlaybookWorkflow", :method_name => "signal")
      end
    end

    it "replaces Timeout with execution_ttl" do
      runner_context = described_class.embedded_ansible({"PlaybookId" => playbook.id, "Timeout" => 30}, secrets, ctx)

      miq_task_id = runner_context["miq_task_id"]
      job         = ManageIQ::Providers::AnsiblePlaybookWorkflow.find_by(:miq_task_id => miq_task_id)

      # EmbeddedAnsible Playbook replaces execution_ttl with timeout when it creates
      # the job, so if we see :timeout in the Job.options we succeeded
      expect(job).to have_attributes(
        :options => hash_including(
          :timeout => 30.minutes
        )
      )
    end

    it "passes credential ids" do
      credential         = FactoryBot.create(:embedded_ansible_credential)
      cloud_credential   = FactoryBot.create(:embedded_ansible_amazon_credential)
      network_credential = FactoryBot.create(:embedded_ansible_network_credential)
      vault_credential   = FactoryBot.create(:embedded_ansible_vault_credential)

      runner_context = described_class.embedded_ansible(
        {
          "PlaybookId"          => playbook.id,
          "CredentialId"        => credential.id,
          "CloudCredentialId"   => cloud_credential.id,
          "NetworkCredentialId" => network_credential.id,
          "VaultCredentialId"   => vault_credential.id
        }, {}, ctx
      )

      miq_task_id = runner_context["miq_task_id"]
      job         = ManageIQ::Providers::AnsiblePlaybookWorkflow.find_by(:miq_task_id => miq_task_id)

      expect(job).to have_attributes(
        :options => hash_including(
          :credentials => [credential.id, cloud_credential.id, network_credential.id, vault_credential.id]
        )
      )
    end
  end

  describe ".provision_execute" do
    let(:params)  { {} }

    it "requires _object_type" do
      runner_context = described_class.provision_execute(params, secrets, create_floe_context(:execution => {"_object_id" => nil}))
      expect(runner_context).to include("running" => false, "success" => false, "output" => failed_task_status("Missing MiqRequestTask type"))
    end

    it "requires _object_id" do
      runner_context = described_class.provision_execute(params, secrets, create_floe_context(:execution => {"_object_type" => "MiqProvision"}))
      expect(runner_context).to include("running" => false, "success" => false, "output" => failed_task_status("Missing MiqRequestTask id"))
    end

    it "requires a provisioning object" do
      floe_context = create_floe_context(FactoryBot.create(:service_reconfigure_task, :request_type => "service_reconfigure"))
      runner_context = described_class.provision_execute(params, secrets, floe_context)
      expect(runner_context).to include("running" => false, "success" => false, "output" => failed_task_status(/Calling provision_execute on non-provisioning request/))
    end

    it "updates task options" do
      task_options = {
        :src_vm_id => FactoryBot.create(:vm_vmware, :ext_management_system => FactoryBot.create(:ems_vmware_with_authentication)).id,
        :param1    => 5,
        :param2    => 4,
        :param3    => 3
      }
      request = FactoryBot.create(:miq_provision_request, :with_approval)
      request.miq_approvals.update_all(:state => "approved")
      task = FactoryBot.create(:miq_provision_vmware, :clone_to_vm, :options => task_options, :miq_request => request)
      floe_context = create_floe_context(task, :input => {:param1 => 1, :param2 => 2})
      runner_context = described_class.provision_execute(params, secrets, floe_context)
      task.reload

      expect(runner_context["miq_request_task_id"]).to eq(task.id)
      expect(task.options).to include(:param1 => 1, :param2 => 2, :param3 => 3)
      expect(task.options.key?(:param4)).to eq(false)
    end
  end

  def create_floe_context(object = nil, execution: nil, input: {})
    execution ||= {"_object_id" => object&.id, "_object_type" => object&.class}.compact

    Floe::Workflow::Context.new({"Execution" => execution}, :input => input.to_json).tap { |ctx| ctx.state["Input"] = input }
  end

  def failed_task_status(cause = nil, error: "States.TaskFailed")
    {"Error" => error, "Cause" => cause}.compact
  end
end
