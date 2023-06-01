RSpec.describe ManageIQ::Providers::Workflows::AutomationManager::WorkflowInstance do
  let(:ems)         { FactoryBot.create(:ems_workflows_automation, :zone => zone) }
  let(:zone)        { EvmSpecHelper.local_miq_server.zone }
  let(:context)     { {"global" => inputs, "current_state" => "FirstState", "states" => []} }
  let(:credentials) { {} }
  let(:inputs)      { {} }

  let(:user)              { FactoryBot.create(:user_with_group) }
  let(:workflow)          { FactoryBot.create(:workflows_automation_workflow, :manager => ems, :payload => payload.to_json, :credentials => credentials) }
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

  before { stub_settings_merge(:prototype => {:ems_workflows => {:enabled => true}}) }

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

    context "with a zone" do
      let(:zone) { FactoryBot.create(:zone) }

      it "queues WorkflowInstance#run on that zone" do
        workflow_instance.run_queue(:zone => zone.name)

        queue_item = MiqQueue.find_by(:class_name => workflow_instance.class.name)
        expect(queue_item.zone).to eq(zone.name)
      end
    end

    context "with a role" do
      it "queues WorkflowInstance#run on that role" do
        workflow_instance.run_queue(:role => "ems_operations")

        queue_item = MiqQueue.find_by(:class_name => workflow_instance.class.name)
        expect(queue_item.role).to eq("ems_operations")
      end
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

    context "with a zone and role" do
      let(:zone) { FactoryBot.create(:zone) }
      let(:payload) do
        {
          "Comment" => "Example Workflow",
          "StartAt" => "FirstState",
          "States"  => {
            "FirstState"   => {
              "Type" => "Pass",
              "Next" => "SuccessState"
            },
            "SuccessState" => {
              "Type" => "Succeed"
            }
          }
        }
      end

      it "requeues with the same queue options" do
        workflow_instance.run(:zone => zone.name, :role => "ems_operations")

        queue_item = MiqQueue.find_by(:class_name => workflow_instance.class.name)
        expect(queue_item).to have_attributes(
          :zone => zone.name,
          :role => "ems_operations"
        )
      end
    end

    context "with a Credentials property in the workflow_content" do
      let(:credentials) { {"username" => "$.my-credential.userid", "password" => "$.my-credential.password"} }
      let(:payload) do
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
        let!(:credential) { FactoryBot.create(:workflows_automation_authentication, :resource => ems, :ems_ref => "my-credential", :name => "My Credential", :userid => "my-user", :password => "shhhh!") }

        before do
          workflow.authentications << credential
          workflow.save!
        end

        it "passes the resolved credential to the runner" do
          expect(Floe::Workflow).to receive(:new).with(payload.to_json, context["global"], {"username" => "my-user", "password" => "shhhh!"}).and_call_original
          workflow_instance.run
        end
      end
    end
  end
end
