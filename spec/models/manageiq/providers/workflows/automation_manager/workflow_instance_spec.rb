RSpec.describe ManageIQ::Providers::Workflows::AutomationManager::WorkflowInstance do
  let(:ems)         { FactoryBot.create(:ems_workflows_automation, :zone => zone) }
  let(:zone)        { EvmSpecHelper.local_miq_server.zone }
  let(:context)     { {"global" => inputs, "current_state" => "FirstState", "states" => []} }
  let(:credentials) { {} }
  let(:inputs)      { {} }

  let(:tenant)            { FactoryBot.create(:tenant) }
  let(:user)              { FactoryBot.create(:user_with_group, :tenant => tenant) }
  let(:workflow)          { FactoryBot.create(:workflows_automation_workflow, :manager => ems, :payload => payload, :credentials => credentials) }
  let(:workflow_instance) { FactoryBot.create(:workflows_automation_workflow_instance, :manager => ems, :parent => workflow, :payload => payload.to_json, :credentials => credentials, :context => context, :miq_task => miq_task, :run_by_userid => user.userid) }
  let(:miq_task)          { nil }
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

  describe "#run_queue" do
    it "queues WorkflowInstance#run" do
      workflow_instance.run_queue

      queue_item = MiqQueue.find_by(:class_name => workflow_instance.class.name)
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

        queue_item = MiqQueue.find_by(:class_name => workflow_instance.class.name)
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
    it "sets the status to success" do
      workflow_instance.run

      expect(workflow_instance.reload.status).to eq("success")
    end

    context "with a Credentials property in the workflow_content" do
      let(:credentials) { {"username" => "$.my-credential.userid", "password" => "$.my-credential.password"} }
      let(:workflow_content) do
        {
          "Comment" => "Example Workflow",
          "StartAt" => "FirstState",
          "States"  => {
            "FirstState" => {
              "Type"        => "Succeed",
              "Credentials" => {
                "username" => "$.username",
                "password" => "$.password"
              }
            }
          }
        }
      end

      context "with a missing Authentication record" do
        it "raises an exception" do
          expect { workflow_instance.run }.to raise_error(ActiveRecord::RecordNotFound, /Couldn't find Authentication/)
        end
      end

      context "with an Authentication record" do
        let(:miq_group)   { evm_owner.current_group }
        let(:evm_owner)   { user }
        let!(:credential) { FactoryBot.create(:workflows_automation_authentication, :resource => ems, :ems_ref => "my-credential", :name => "My Credential", :miq_group => miq_group, :userid => "my-user", :password => "shhhh!") }

        it "passes the resolved credential to the runner" do
          expect(Floe::Workflow).to receive(:new).with(workflow_content, context["global"], {"username" => "my-user", "password" => "shhhh!"}).and_call_original
          workflow_instance.run
        end

        context "from another tenant" do
          let(:user2)     { FactoryBot.create(:user_with_group) }
          let(:evm_owner) { user2 }

          it "raises an exception" do
            expect { workflow_instance.run }.to raise_error(ActiveRecord::RecordNotFound, /Couldn't find Authentication/)
          end
        end
      end
    end
  end
end
