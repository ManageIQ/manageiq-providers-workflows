RSpec.describe ManageIQ::Providers::Workflows::BuiltinRunnner do
  require "floe"

  let(:subject) { described_class.new(options) }
  let(:options) { {} }
  let(:ctx)     { Floe::Workflow::Context.new }

  describe "run_async!" do
    it "with an invalid resource" do
      expect { subject.run_async!("docker://foo", {}, {}, ctx) }.to raise_error(ArgumentError, "Invalid resource")
    end

    it "with an invalid method" do
      result = subject.run_async!("manageiq://invalid_method", {}, {}, ctx)
      expect(result).to include(
        "running" => false,
        "success" => false,
        "output"  => {
          "Error" => "States.TaskFailed",
          "Cause" => "undefined method [invalid_method]"
        }
      )
    end
  end
end
