RSpec.describe ManageIQ::Providers::Workflows::AutomationManager::WorkflowInstance do
  let(:ems)         { FactoryBot.create(:ems_workflows_automation, :zone => zone) }
  let(:zone)        { EvmSpecHelper.local_miq_server.zone }
  let(:context)     { {"global" => inputs, "current_state" => "FirstState", "states" => []} }
  let(:credentials) { {} }
  let(:inputs)      { {} }

  let(:workflow)          { FactoryBot.create(:workflows_automation_workflow, :ext_management_system => ems, :workflow_content => workflow_content, :credentials => credentials) }
  let(:workflow_instance) { FactoryBot.create(:workflows_automation_workflow_instance, :workflow => workflow, :workflow_content => workflow_content, :credentials => credentials, :context => context, :miq_task => miq_task) }
  let(:miq_task)          { nil }
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

  describe "#run_queue" do
    it "queues WorkflowInstance#run" do
      workflow_instance.run_queue

      queue_item = MiqQueue.first
      expect(queue_item).to have_attributes(
        :class_name  => workflow_instance.class.name,
        :instance_id => workflow_instance.id,
        :method_name => "run"
      )
    end

    context "with a miq_task" do
      let(:miq_task) { FactoryBot.create(:miq_task) }

      it "adds a callback if a miq_task is present" do
        workflow_instance.run_queue

        queue_item = MiqQueue.first
        expect(queue_item).to have_attributes(
          :miq_callback => {
            :class_name  => workflow_instance.class.name,
            :instance_id => workflow_instance.id,
            :method_name => :queue_callback
          }
        )
      end
    end
  end

  describe "#run" do
    it "test" do
      workflow_instance.run

      expect(workflow_instance.reload.status).to eq("success")
    end
  end
end
