RSpec.describe ManageIQ::Providers::Workflows::AutomationManager::Workflow do
  let(:ems)         { FactoryBot.create(:ems_workflows_automation, :zone => zone) }
  let(:zone)        { EvmSpecHelper.local_miq_server.zone }
  let(:workflow)    { FactoryBot.create(:workflows_automation_workflow, :ext_management_system => ems, :workflow_content => workflow_content, :credentials => credentials) }
  let(:credentials) { {} }
  let(:inputs)      { {} }
  let(:workflow_content) do
    JSON.parse(
      <<~WORKFLOW_CONTENT
        {
          "Comment": "Example Workflow",
          "StartAt": "FirstState",
          "States": {
            "FirstState": {
              "Type": "Succeed"
            }
          }
        }
      WORKFLOW_CONTENT
    )
  end

  describe "#execute" do
    it "creates the workflow_instance" do
      workflow.execute(:inputs => inputs)

      expect(workflow.workflow_instances.count).to eq(1)
      expect(ems.workflow_instances.count).to eq(1)
      expect(ems.workflow_instances.first).to have_attributes(
        :ext_management_system => workflow.ext_management_system,
        :type                  => "ManageIQ::Providers::Workflows::AutomationManager::WorkflowInstance",
        :workflow_content      => workflow.workflow_content,
        :credentials           => workflow.credentials,
        :context               => {"global" => inputs, "current_state" => "FirstState", "states" => []},
        :output                => {},
        :status                => "pending"
      )
    end

    it "returns the task id" do
      miq_task_id = workflow.execute(:inputs => inputs)
      expect(MiqTask.find(miq_task_id)).to have_attributes(
        :name => "Execute Workflow"
      )
    end

    it "queues WorkflowInstance#run" do
      workflow.execute(:inputs => inputs)

      workflow_instance = ems.workflow_instances.first

      expect(MiqQueue.count).to eq(1)

      queue_item = MiqQueue.first
      expect(queue_item).to have_attributes(
        :class_name  => "#{ems.class}::WorkflowInstance",
        :instance_id => workflow_instance.id,
        :method_name => "run"
      )
    end

    it "defaults to admin userid" do
      workflow.execute(:inputs => inputs)

      workflow_instance = ems.workflow_instances.first
      expect(workflow_instance.userid).to eq("admin")
      expect(workflow_instance.miq_task.userid).to eq("admin")
    end

    context "with another user" do
      let(:user) { FactoryBot.create(:user) }

      it "uses the userid provided" do
        workflow.execute(:userid => user.userid)

        workflow_instance = ems.workflow_instances.first
        expect(workflow_instance.userid).to eq(user.userid)
        expect(workflow_instance.miq_task.userid).to eq(user.userid)
      end
    end
  end
end
