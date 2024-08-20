RSpec.describe ManageIQ::Providers::Workflows::AutomationManager::Workflow do
  let(:ems)         { FactoryBot.create(:ems_workflows_automation, :zone => zone) }
  let(:zone)        { EvmSpecHelper.local_miq_server.zone }
  let(:workflow)    { FactoryBot.create(:workflows_automation_workflow, :manager => ems, :payload => payload.to_json, :credentials => credentials) }
  let(:credentials) { {} }
  let(:inputs)      { {} }
  let(:payload) do
    {
      "Comment" => "Example Workflow",
      "StartAt" => "FirstState",
      "States"  => {
        "FirstState" => {
          "Type" => "Succeed"
        }
      }
    }
  end

  describe "#run" do
    it "creates the workflow_instance" do
      workflow.run(:inputs => inputs)

      expect(workflow.children.count).to eq(1)
      expect(ems.configuration_scripts.count).to eq(1)

      workflow_instance = ems.configuration_scripts.first
      expect(workflow_instance).to have_attributes(
        :manager     => workflow.manager,
        :type        => "ManageIQ::Providers::Workflows::AutomationManager::WorkflowInstance",
        :name        => workflow.name,
        :payload     => workflow.payload,
        :credentials => workflow.credentials,
        :context     => {"Execution" => hash_including("Id" => workflow_instance.manager_ref, "Input" => inputs), "State" => {}, "StateMachine" => {}, "StateHistory" => [], "Task" => {}},
        :output      => {},
        :status      => "pending"
      )
    end

    it "returns the task id" do
      miq_task_id = workflow.run(:inputs => inputs)
      expect(MiqTask.find(miq_task_id)).to have_attributes(
        :name => "Execute Workflow"
      )
    end

    it "queues WorkflowInstance#run" do
      workflow.run(:inputs => inputs)

      workflow_instance = ems.configuration_scripts.first

      expect(MiqQueue.count).to eq(1)

      queue_item = MiqQueue.first
      expect(queue_item).to have_attributes(
        :class_name  => "#{ems.class}::WorkflowInstance",
        :instance_id => workflow_instance.id,
        :method_name => "run"
      )
    end

    it "defaults to admin userid" do
      workflow.run(:inputs => inputs)

      workflow_instance = ems.configuration_scripts.first
      expect(workflow_instance.run_by_userid).to eq("system")
      expect(workflow_instance.miq_task.userid).to eq("system")
    end

    it "defaults to automate role" do
      workflow.run(:inputs => inputs)

      workflow_instance = ems.configuration_scripts.first
      queue_item = MiqQueue.find_by(:class_name => workflow_instance.class.name, :method_name => "run")

      expect(queue_item.role).to eq("automate")
    end

    context "with an active webservices server" do
      let(:ipaddress) { "1.2.3.4" }
      let(:hostname)  { "manageiq.localdomain" }
      let!(:web_server) do
        FactoryBot.create(
          :miq_server,
          :has_active_webservices => true,
          :hostname               => hostname,
          :ipaddress              => ipaddress
        )
      end

      it "adds remote_ws_url to the context" do
        workflow.run(:inputs => inputs)
        workflow_instance = ems.configuration_scripts.first

        expected_api_url = URI::HTTPS.build(:host => ipaddress).to_s
        expect(workflow_instance.context["Execution"]).to include("_manageiq_api_url" => expected_api_url)
      end
    end

    context "with another user" do
      let(:user) { FactoryBot.create(:user) }

      it "uses the userid provided" do
        workflow.run(:userid => user.userid)

        workflow_instance = ems.configuration_scripts.first
        expect(workflow_instance.run_by_userid).to eq(user.userid)
        expect(workflow_instance.miq_task.userid).to eq(user.userid)
      end
    end

    context "with a zone" do
      let(:zone) { FactoryBot.create(:zone) }

      it "uses the provided zone" do
        workflow.run(:zone => zone.name)

        workflow_instance = ems.configuration_scripts.first
        queue_item = MiqQueue.find_by(:class_name => workflow_instance.class.name, :method_name => "run")

        expect(queue_item.zone).to eq(zone.name)
      end
    end
  end
end
