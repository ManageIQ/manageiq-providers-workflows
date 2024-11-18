RSpec.describe ManageIQ::Providers::Workflows::Runner do
  require "floe"

  let(:subject)  { described_class.new }
  let(:workflow_instance) { FactoryBot.create(:workflows_automation_workflow_instance) }
  let(:queue_args) { {:role => "automate"} }

  describe ".add_workflow" do
    it "adds the workflow to the workflows hash" do
      subject.add_workflow_instance(workflow_instance, queue_args)
      expect(subject.workflow_instances.count).to eq(1)
      expect(subject.workflow_instances[workflow_instance.manager_ref]).to eq([workflow_instance, queue_args])
    end
  end

  describe ".delete_workflow" do
    context "with nothing in #workflows" do
      it "doesn't throw an exception" do
        expect(subject.delete_workflow_instance(workflow_instance)).to be_nil
      end
    end

    context "with a workflow in #workflows" do
      before { subject.add_workflow_instance(workflow_instance, queue_args) }

      it "deletes the workflow from #workflows" do
        subject.delete_workflow_instance(workflow_instance)
        expect(subject.workflow_instances).to be_empty
      end
    end
  end

  describe "#docker_wait (private)" do
    let(:docker_runner) { double("Floe::ContainerRunner::Docker") }
    let(:execution_id)  { SecureRandom.uuid }
    let(:container_ref) { SecureRandom.uuid }
    let(:event)         { "create" }
    let(:data)          { {"execution_id" => execution_id, "runner_context" => {"container_ref" => container_ref}} }

    before do
      allow(Floe::Runner).to receive(:for_resource).with("docker").and_return(docker_runner)
      allow(docker_runner).to receive(:wait).and_yield(event, data)
    end

    context "with no workflows in #workflow_instances" do
      it "doesn't queue an update for an unrecognized workflow" do
        subject.send(:docker_wait)

        expect(MiqQueue.count).to be_zero
      end
    end

    context "with a workflow_instance registered with this runner" do
      let(:workflow_instance) { FactoryBot.create(:workflows_automation_workflow_instance, :manager_ref => execution_id) }
      let(:queue_args)        { {:zone => nil, :role => "automate"} }
      before { subject.add_workflow_instance(workflow_instance, queue_args) }

      it "queues a run for the workflow instance" do
        subject.send(:docker_wait)

        expect(MiqQueue.count).to eq(1)
        expect(MiqQueue.first).to have_attributes(
          :class_name  => "ManageIQ::Providers::Workflows::AutomationManager::WorkflowInstance",
          :method_name => "run",
          :args        => [{:zone => nil, :role => "automate"}],
        )
      end

      context "with an object in queue_args" do
        let(:service)    { FactoryBot.create(:service) }
        let(:queue_args) { {:zone => nil, :role => "automate", :object_type => service.class.name, :object_id => service.id} }

        it "queues a run for the workflow instance" do
          subject.send(:docker_wait)

          expect(MiqQueue.count).to eq(1)
          expect(MiqQueue.first).to have_attributes(
            :class_name  => "ManageIQ::Providers::Workflows::AutomationManager::WorkflowInstance",
            :method_name => "run",
            :args        => [{:zone => nil, :role => "automate", :object_type => service.class.name, :object_id => service.id}],
          )
        end
      end
    end
  end
end
