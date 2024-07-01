RSpec.describe ManageIQ::Providers::Workflows::Runner do
  require "floe"

  let(:subject)  { described_class.new }
  let(:workflow) { FactoryBot.create(:workflows_automation_workflow_instance) }
  let(:queue_args) { {:role => "automate"} }

  describe ".add_workflow" do
    it "adds the workflow to the workflows hash" do
      subject.add_workflow(workflow, queue_args)
      expect(subject.workflows.count).to eq(1)
      expect(subject.workflows[workflow.id]).to eq([workflow, queue_args])
    end
  end

  describe ".delete_workflow" do
    context "with nothing in #workflows" do
      it "doesn't throw an exception" do
        expect(subject.delete_workflow(workflow)).to be_nil
      end
    end

    context "with a workflow in #workflows" do
      before { subject.add_workflow(workflow, queue_args) }

      it "deletes the workflow from #workflows" do
        subject.delete_workflow(workflow)
        expect(subject.workflows).to be_empty
      end
    end
  end
end
