RSpec.describe ManageIQ::Providers::Workflows::BuiltinMethods do
  require "floe"

  describe ".email" do
    let(:params) { {"To" => "foo@bar.com", "From" => "baz@bar.com"} }

    context "with no notifier" do
      it "calls GenericMailer" do
        runner_context = described_class.email(params)
        expect(runner_context).to have_key("miq_task_id")
        expect(MiqTask.find_by(:id => runner_context["miq_task_id"])).to have_attributes(:state => "Finished", :status => "Error")
      end
    end
  end

  describe ".provision_execute" do
    let(:params)  { {} }
    let(:secrets) { {} }

    it "returns an error if _object_type isn't passed" do
      runner_context = described_class.provision_execute(params, secrets, Floe::Workflow::Context.new({"Execution" => {"_object_id" => nil}}))
      expect(runner_context).to include("running" => false, "success" => false, "output" => {"Error" => "States.TaskFailed", "Cause" => "Missing MiqRequestTask type"})
    end

    it "returns an error if _object_id isn't passed" do
      runner_context = described_class.provision_execute(params, secrets, Floe::Workflow::Context.new({"Execution" => {"_object_type" => "MiqProvision"}}))
      expect(runner_context).to include("running" => false, "success" => false, "output" => {"Error" => "States.TaskFailed", "Cause" => "Missing MiqRequestTask id"})
    end
  end
end
