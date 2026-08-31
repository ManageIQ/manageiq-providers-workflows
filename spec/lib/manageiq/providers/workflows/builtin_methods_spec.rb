RSpec.describe ManageIQ::Providers::Workflows::BuiltinMethods do
  require "floe"

  let(:ctx) { Floe::Workflow::Context.new }
  let(:secrets) { {} }

  describe ".api" do
    let(:faraday_stub) { double("Faraday::Connection") }
    let(:ctx) { Floe::Workflow::Context.new({"Execution" => {"_manageiq_api_url" => "http://localhost:3000"}}) }

    before do
      require "faraday"
      allow(Faraday).to receive(:new).and_return(faraday_stub)
      allow(faraday_stub).to receive(:response).with(:follow_redirects)
      allow(faraday_stub).to receive(:response).with(:json)
      allow(faraday_stub).to receive(:request).with(:json)
    end

    it "uses the API URL from the execution context" do
      expect(Faraday).to receive(:new).with(hash_including(:url => "http://localhost:3000/api/auth")).and_return(faraday_stub)
      expect(faraday_stub).to receive(:get).and_return(Faraday::Response.new(:status => 200, :body => "{}"))

      params = {"Path" => "/api/auth"}
      runner_context = described_class.api(params, secrets, ctx)
      expect(runner_context)
        .to include(
          "running" => false,
          "success" => true,
          "output"  => {"Body" => "{}", "Headers" => nil, "Status" => 200}
        )
    end

    it "uses the URL from Params if it is present" do
      expect(Faraday).to receive(:new).with(hash_including(:url => "https://manageiq-api-server/api/auth")).and_return(faraday_stub)
      expect(faraday_stub).to receive(:get).and_return(Faraday::Response.new(:status => 200, :body => "{}"))

      params = {"Url" => "https://manageiq-api-server/api/auth"}
      runner_context = described_class.api(params, secrets, ctx)
      expect(runner_context)
        .to include(
          "running" => false,
          "success" => true,
          "output"  => {"Body" => "{}", "Headers" => nil, "Status" => 200}
        )
    end

    it "returns an error if both Path and Url are provided" do
      params = {"Url" => "https://manageiq-api-server/api/auth", "Path" => "/api/auth"}
      runner_context = described_class.api(params, secrets, ctx)
      expect(runner_context)
        .to include(
          "running" => false,
          "success" => false,
          "output"  => {"Cause" => "You must provide either Url or Path, not both", "Error" => "States.TaskFailed"}
        )
    end

    it "adds a Basic authorization header if username and password is passed in Credentials" do
      expect(Faraday)
        .to receive(:new)
        .with(
          hash_including(
            :url     => "http://localhost:3000/api/auth",
            :headers => hash_including("Authorization" => "Basic #{Base64.strict_encode64("admin:password")}")
          )
        )
        .and_return(faraday_stub)
      expect(faraday_stub).to receive(:get).and_return(Faraday::Response.new(:status => 200, :body => "{}"))

      params  = {"Path" => "/api/auth"}
      secrets = {"username" => "admin", "password" => "password"}

      runner_context = described_class.api(params, secrets, ctx)
      expect(runner_context)
        .to include(
          "running" => false,
          "success" => true,
          "output"  => {"Body" => "{}", "Headers" => nil, "Status" => 200}
        )
    end

    it "adds a Bearer authorization header if bearer_token is passed in Credentials" do
      expect(Faraday)
        .to receive(:new)
        .with(
          hash_including(
            :url     => "http://localhost:3000/api/auth",
            :headers => hash_including("Authorization" => "Bearer abcdefg")
          )
        )
        .and_return(faraday_stub)
      expect(faraday_stub).to receive(:get).and_return(Faraday::Response.new(:status => 200, :body => "{}"))

      params  = {"Path" => "/api/auth"}
      secrets = {"bearer_token" => "abcdefg"}

      runner_context = described_class.api(params, secrets, ctx)
      expect(runner_context)
        .to include(
          "running" => false,
          "success" => true,
          "output"  => {"Body" => "{}", "Headers" => nil, "Status" => 200}
        )
    end

    it "Bearer token takes precedence if username/password also passed" do
      expect(Faraday)
        .to receive(:new)
        .with(
          hash_including(
            :url     => "http://localhost:3000/api/auth",
            :headers => hash_including("Authorization" => "Bearer abcdefg")
          )
        )
        .and_return(faraday_stub)
      expect(faraday_stub).to receive(:get).and_return(Faraday::Response.new(:status => 200, :body => "{}"))

      params  = {"Path" => "/api/auth"}
      secrets = {"username" => "admin", "password" => "password", "bearer_token" => "abcdefg"}

      runner_context = described_class.api(params, secrets, ctx)
      expect(runner_context)
        .to include(
          "running" => false,
          "success" => true,
          "output"  => {"Body" => "{}", "Headers" => nil, "Status" => 200}
        )
    end
  end

  describe ".http" do
    let(:faraday_stub) { double("Faraday::Connection") }

    before do
      require "faraday"
      allow(Faraday).to receive(:new).and_return(faraday_stub)
      allow(faraday_stub).to receive(:response).with(:follow_redirects)
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

  describe ".provision_task" do
    it "requires _object_type" do
      runner_context = described_class.provision_task({}, secrets, create_floe_context(:execution => {"_object_id" => 1}))
      expect(runner_context).to include("running" => false, "success" => false, "output" => failed_task_status("Missing MiqRequestTask type"))
    end

    it "requires _object_id" do
      runner_context = described_class.provision_task({}, secrets, create_floe_context(:execution => {"_object_type" => "ServiceTemplateProvisionTask"}))
      expect(runner_context).to include("running" => false, "success" => false, "output" => failed_task_status("Missing MiqRequestTask id"))
    end

    it "returns an error when the MiqRequestTask cannot be found" do
      runner_context = described_class.provision_task({}, secrets, create_floe_context(:execution => {"_object_type" => "ServiceTemplateProvisionTask", "_object_id" => 0}))
      expect(runner_context).to include("running" => false, "success" => false, "output" => failed_task_status("Unable to find MiqReqeustTask id: [0]"))
    end

    context "VM Provision" do
      let(:ems)     { FactoryBot.create(:ems_vmware_with_authentication) }
      let(:source)  { FactoryBot.create(:template_vmware, :ext_management_system => ems) }
      let(:request) { FactoryBot.create(:service_template_provision_request, :with_approval).tap { |r| r.miq_approvals.update_all(:state => "approved") } }
      let(:task)    { FactoryBot.create(:service_template_provision_task, :miq_request => request, :userid => "admin") }
      let(:params)  { {"request_type" => "template", "options" => {"src_vm_id" => [source.id, source.name]}} }

      it "creates an MiqProvision linked to the service task" do
        floe_context   = create_floe_context(task)
        runner_context = described_class.provision_task(params, secrets, floe_context)

        miq_provision = MiqProvision.find(runner_context["miq_request_task_id"])
        expect(miq_provision).to be_kind_of(ems.class.provision_class(nil))
        expect(miq_provision).to have_attributes(
          :source           => source,
          :miq_request      => request,
          :miq_request_task => task,
          :userid           => task.userid,
          :request_type     => "template"
        )
        expect(runner_context).to include("_manageiq_api_url" => "http://localhost:3000")
      end

      it "merges extra params into the provision attributes" do
        floe_context   = create_floe_context(task)
        runner_context = described_class.provision_task(params.merge("description" => "my provision task"), secrets, floe_context)

        miq_provision = MiqProvision.find(runner_context["miq_request_task_id"])
        expect(miq_provision).to have_attributes(:description => "my provision task")
      end

      context "with an invalid request_type" do
        let(:params)  { {"request_type" => "typo", "options" => {"src_vm_id" => [source.id, source.name]}} }

        it "returns an error" do
          runner_context = described_class.provision_task(params, secrets, create_floe_context(task))
          expect(runner_context).to include("running" => false, "success" => false, "output" => failed_task_status("Unable to find MiqReqeust class from request_type: [typo]"))
        end
      end
    end

    context "ConfigurationScript Provisioning" do
      let(:ems)     { FactoryBot.create(:embedded_automation_manager_terraform) }
      let(:request) { FactoryBot.create(:service_template_provision_request, :with_approval).tap { |r| r.miq_approvals.update_all(:state => "approved") } }
      let(:task)    { FactoryBot.create(:service_template_provision_task, :miq_request => request, :userid => "admin") }
      let(:source)  { FactoryBot.create(:configuration_script_embedded_terraform, :manager => ems) }
      let(:params)  { {"request_type" => "provision_via_automation_manager", "source_type" => "ConfigurationScript", "source_id" => source.id, "options" => {"src_configuration_script_id" => [source.id, source.name]}} }

      it "creates a Provision task linked to the service task" do
        floe_context   = create_floe_context(task)
        runner_context = described_class.provision_task(params, secrets, floe_context)

        prov_task = MiqProvisionTask.find(runner_context["miq_request_task_id"])
        expect(prov_task).to be_kind_of(ems.class.provision_class(nil))
        expect(prov_task).to have_attributes(
          :source           => source,
          :miq_request      => request,
          :miq_request_task => task,
          :userid           => task.userid
        )
        expect(runner_context).to include("_manageiq_api_url" => "http://localhost:3000")
      end
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

    context "with a miq_provision_task" do
      let(:ems)     { FactoryBot.create(:ems_vmware_with_authentication) }
      let(:request) { FactoryBot.create(:miq_provision_request, :with_approval).tap { |r| r.miq_approvals.update_all(:state => "approved") } }
      let(:source)  { FactoryBot.create(:template_vmware, :ext_management_system => ems) }
      let(:dest)    { FactoryBot.create(:vm_vmware, :ext_management_system => ems) }
      let(:options) { {:src_vm_id => source.id, :vm_name => "myvm", :memory_mb => 1_024} }
      let(:task)    { FactoryBot.create(:miq_provision_vmware, :clone_to_vm, :options => options, :miq_request => request) }

      it "updates task options" do
        floe_context = create_floe_context(task, :input => {:vm_name => "myvm2", :cpu_sockets => 2})
        runner_context = described_class.provision_execute(params, secrets, floe_context)
        task.reload

        expect(runner_context["miq_request_task_id"]).to eq(task.id)
        expect(task.options).to include(:vm_name => "myvm2", :memory_mb => 1_024)
        expect(task.options.keys).not_to include(:cpu_sockets)
      end

      it "returns the miq_request_task info" do
        floe_context = create_floe_context(task)
        runner_context = described_class.provision_execute(params, secrets, floe_context)
        task.update!(:state => "provisioned", :status => "Ok", :destination => dest)
        described_class.send(:provision_execute_status!, runner_context)

        expect(runner_context["output"]).to include(
          "id"          => task.id,
          "href"        => "http://localhost:3000/api/request_tasks/#{task.id}",
          "state"       => "provisioned",
          "status"      => "Ok",
          "source"      => {"id" => source.id, "href" => "http://localhost:3000/api/templates/#{source.id}"},
          "destination" => {"id" => dest.id,   "href" => "http://localhost:3000/api/vms/#{dest.id}"}
        )
      end
    end
  end

  describe ".retire_execute" do
    let(:params) { {} }
    let(:ems)    { FactoryBot.create(:ems_vmware_with_authentication, :zone => zone) }
    let(:vm)     { FactoryBot.create(:vm_vmware, :ext_management_system => ems) }
    let(:zone)   { EvmSpecHelper.local_miq_server.zone }
    let(:retire_request) { FactoryBot.create(:service_retire_request).tap { |r| r.miq_approvals.update_all(:state => "approved") } }
    let(:retire_task) do
      FactoryBot.create(:vm_retire_task, :options => {:src_vm_id => vm.id}, :miq_request => retire_request)
    end

    it "requires _object_type" do
      runner_context = described_class.retire_execute(params, secrets, create_floe_context(:execution => {"_object_id" => nil}))
      expect(runner_context).to include("running" => false, "success" => false, "output" => failed_task_status("Missing MiqRequestTask type"))
    end

    it "requires _object_id" do
      runner_context = described_class.retire_execute(params, secrets, create_floe_context(:execution => {"_object_type" => "MiqProvision"}))
      expect(runner_context).to include("running" => false, "success" => false, "output" => failed_task_status("Missing MiqRequestTask id"))
    end

    it "requires a retire task" do
      floe_context = create_floe_context(FactoryBot.create(:service_reconfigure_task, :request_type => "service_reconfigure"))
      runner_context = described_class.retire_execute(params, secrets, floe_context)
      expect(runner_context).to include("running" => false, "success" => false, "output" => failed_task_status(/Calling retire_execute on non-retire request/))
    end

    context "passing options with Parameters" do
      let(:params) { {"RemovalType" => "remove_from_disk", "DeleteFromVmdb" => true} }
      it "updates task options" do
        floe_context = create_floe_context(retire_task)
        runner_context = described_class.retire_execute(params, secrets, floe_context)
        retire_task.reload

        expect(runner_context["miq_request_task_id"]).to eq(retire_task.id)
        expect(retire_task.options).to include(:removal_type => "remove_from_disk", :delete_from_vmdb => true)
      end
    end
  end

  def create_floe_context(object = nil, execution: nil, input: {})
    execution ||= {"_object_id" => object&.id, "_object_type" => object&.class, "_manageiq_api_url" => "http://localhost:3000"}.compact

    Floe::Workflow::Context.new({"Execution" => execution}, :input => input.to_json).tap { |ctx| ctx.state["Input"] = input }
  end

  def failed_task_status(cause = nil, error: "States.TaskFailed")
    {"Error" => error, "Cause" => cause}.compact
  end
end
