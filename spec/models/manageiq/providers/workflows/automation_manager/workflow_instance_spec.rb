RSpec.describe ManageIQ::Providers::Workflows::AutomationManager::WorkflowInstance do
  let(:ems)         { FactoryBot.create(:ems_workflows_automation, :zone => zone) }
  let(:zone)        { EvmSpecHelper.local_miq_server.zone }
  let(:workflow)    { FactoryBot.create(:workflows_automation_workflow, :ext_management_system => ems, :workflow_content => workflow_content, :credentials => credentials) }
  let(:credentials) { {} }
  let(:inputs)      { {} }

  let(:workflow_instance) { FactoryBot.create(:workflows_automation_workflow_instance, :workflow => workflow, :credentials => credentials, :miq_task => miq_task) }
  let(:miq_task)          { nil }
  let(:workflow_content) do
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
end
