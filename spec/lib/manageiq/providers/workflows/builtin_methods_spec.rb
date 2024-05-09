RSpec.describe ManageIQ::Providers::Workflows::BuiltinMethods do
  require "floe"

  describe ".email" do
    let(:params) { {"To" => "foo@bar.com", "From" => "baz@bar.com"} }

    context "with no notifier" do
      it "calls GenericMailer" do
        runner_context = described_class.email(params)
        expect(runner_context).to have_key("miq_task_id")
        expect(MiqTask.find_by(:id => runner_context["miq_task_id"])).to have_attributes(:state => "Queued", :status => "Error")
      end
    end
  end

  describe ".provision_execute" do
    let(:params)  { {} }
    let(:secrets) { {} }
    let(:context) { Floe::Workflow::Context.new({}) }

    it "returns an error if _object isn't passed" do
      runner_context = described_class.provision_execute(params, secrets, context)
      expect(runner_context).to include("running" => false, "success" => false, "output" => {"Error" => "States.TaskFailed", "Cause" => "Calling provision_execute on non-provisioning request: []"})
    end
  end
end
