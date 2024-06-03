RSpec.describe ManageIQ::Providers::Workflows::BuiltinMethods do
  require "floe"

  describe ".email" do
    let(:params) { {"To" => "foo@bar.com", "From" => "baz@bar.com"} }

    context "with no notifier" do
      it "fails emailing" do
        runner_context = described_class.email(params)
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

        runner_context = described_class.email({"To" => "foo@bar.com"})

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

  describe ".provision_execute" do
    let(:params)  { {} }
    let(:secrets) { {} }

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

    it "updates task options" do
      task_options = {
        :src_vm_id => FactoryBot.create(:vm_vmware, :ext_management_system => FactoryBot.create(:ems_vmware_with_authentication)).id,
        :param1    => 5,
        :param2    => 4,
        :param3    => 3
      }
      request = FactoryBot.create(:miq_provision_request, :with_approval)
      request.miq_approvals.update_all(:state => "approved")
      task = FactoryBot.create(:miq_provision_vmware, :clone_to_vm, :options => task_options, :miq_request => request)
      floe_context = create_floe_context(task, :input => {:param1 => 1, :param2 => 2})
      runner_context = described_class.provision_execute(params, secrets, floe_context)
      task.reload

      expect(runner_context["miq_request_task_id"]).to eq(task.id)
      expect(task.options).to include(:param1 => 1, :param2 => 2, :param3 => 3)
      expect(task.options.key?(:param4)).to eq(false)
    end
  end

  def create_floe_context(object = nil, execution: nil, input: {})
    execution ||= {"_object_id" => object&.id, "_object_type" => object&.class}.compact

    Floe::Workflow::Context.new({"Execution" => execution}, :input => input).tap { |ctx| ctx.state["Input"] = input }
  end

  def failed_task_status(cause = nil, error: "States.TaskFailed")
    {"Error" => error, "Cause" => cause}.compact
  end
end
