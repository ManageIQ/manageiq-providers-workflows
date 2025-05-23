RSpec.describe ManageIQ::Providers::Workflows::AutomationManager::WorkflowInstance do
  let(:ems)         { FactoryBot.create(:ems_workflows_automation, :zone => zone) }
  let(:zone)        { EvmSpecHelper.local_miq_server.zone }
  let(:context)     { Floe::Workflow::Context.new(:input => input.to_json) }
  let(:credentials) { {} }
  let(:input)       { {"foo" => "bar"} }

  let(:user)              { FactoryBot.create(:user_with_group) }
  let(:workflow)          { FactoryBot.create(:workflows_automation_workflow, :manager => ems, :payload => payload.to_json, :credentials => credentials) }
  let(:workflow_instance) { FactoryBot.create(:workflows_automation_workflow_instance, :manager => ems, :parent => workflow, :payload => payload.to_json, :credentials => credentials, :context => context.to_h, :miq_task => miq_task, :run_by_userid => user.userid) }
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

    context "with a zone" do
      let(:zone) { FactoryBot.create(:zone) }

      it "queues WorkflowInstance#run on that zone" do
        workflow_instance.run_queue(:zone => zone.name)

        queue_item = MiqQueue.find_by(:class_name => workflow_instance.class.name)
        expect(queue_item.zone).to eq(zone.name)

        queue_item.deliver
        expect(workflow_instance.reload.status).to eq("success")
      end
    end

    context "with a role" do
      it "queues WorkflowInstance#run on that role" do
        workflow_instance.run_queue(:role => "ems_operations")

        queue_item = MiqQueue.find_by(:class_name => workflow_instance.class.name)
        expect(queue_item.role).to eq("ems_operations")

        queue_item.deliver
        expect(workflow_instance.reload.status).to eq("success")
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

        queue_item.deliver
        expect(workflow_instance.reload.status).to eq("success")
      end

      it "updates the task status" do
        workflow_instance.run_queue

        queue_item = MiqQueue.find_by(:class_name => workflow_instance.class.name)
        queue_item.deliver_and_process
        expect(workflow_instance.miq_task.reload).to have_attributes(:state => "Finished", :status => "Ok", :message => "Workflow completed successfully")
      end

      context "with a workflow failure" do
        let(:payload) do
          {
            "Comment" => "Example Workflow",
            "StartAt" => "FirstState",
            "States"  => {
              "FirstState" => {
                "Type"  => "Fail",
                "Error" => "Failed!"
              }
            }
          }
        end

        it "updates the task status" do
          workflow_instance.run_queue

          queue_item = MiqQueue.find_by(:class_name => workflow_instance.class.name)
          queue_item.deliver_and_process
          expect(workflow_instance.miq_task.reload).to have_attributes(:state => "Finished", :status => "Error", :message => "Workflow failed")
        end
      end
    end
  end

  describe "#run" do
    it "sets the status to success" do
      workflow_instance.run

      expect(workflow_instance.reload.status).to eq("success")
    end

    it "sets the workflow output" do
      workflow_instance.run

      expect(workflow_instance.reload.output).to eq("foo" => "bar")
    end

    context "with credentials=nil" do
      let(:credentials) { nil }

      it "sets the status to success" do
        workflow_instance.run

        expect(workflow_instance.reload.status).to eq("success")
      end
    end

    context "with a workflow that sets a credential" do
      let(:payload) do
        {
          "Comment" => "Example Workflow",
          "StartAt" => "FirstState",
          "States"  => {
            "FirstState" => {
              "Type"       => "Pass",
              "Result"     => {"Bearer" => "TOKEN"},
              "ResultPath" => "$.Credentials",
              "End"        => true
            }
          }
        }
      end

      it "adds the credential to the credentials jsonb hash" do
        workflow_instance.run

        expected_value = ManageIQ::Password.encrypt("TOKEN")
        expect(workflow_instance.reload.credentials).to include("Bearer" => expected_value)
      end

      context "with credentials=nil" do
        let(:credentials) { nil }

        it "sets the status to success" do
          workflow_instance.run

          expect(workflow_instance.reload.status).to eq("success")
          expected_value = ManageIQ::Password.encrypt("TOKEN")
          expect(workflow_instance.reload.credentials).to include("Bearer" => expected_value)
        end
      end

      context "with an existing value" do
        let(:credentials) { {"Bearer" => "OLD_TOKEN"} }

        it "updates the credential in the credentials jsonb hash" do
          workflow_instance.run

          expected_value = ManageIQ::Password.encrypt("TOKEN")
          expect(workflow_instance.reload.credentials).to include("Bearer" => expected_value)
        end
      end
    end

    context "with a zone and role" do
      let(:zone) { EvmSpecHelper.local_miq_server.zone }
      let(:payload) do
        {
          "Comment" => "Example Workflow",
          "StartAt" => "FirstState",
          "States"  => {
            "FirstState"   => {
              "Type"    => "Wait",
              "Seconds" => 10,
              "Next"    => "SuccessState"
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
      let(:credentials) { {"username.$" => {"credential_ref" => "my-credential", "credential_field" => "userid"}, "password.$" => {"credential_ref" => "my-credential", "credential_field" => "password"}} }
      let(:payload) do
        {
          "Comment" => "Example Workflow",
          "StartAt" => "FirstState",
          "States"  => {
            "FirstState" => {
              "Type"        => "Succeed",
              "Credentials" => {
                "username.$" => "$.username",
                "password.$" => "$.password"
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
          # second argument is a new Context that was created with context.to_h
          expect(Floe::Workflow).to receive(:new).with(payload.to_json, anything, {"username" => "my-user", "password" => "shhhh!"}).and_call_original
          workflow_instance.run
        end

        context "with a state that sets a credential" do
          let(:payload) do
            {
              "Comment" => "Example Workflow",
              "StartAt" => "FirstState",
              "States"  => {
                "FirstState" => {
                  "Type"        => "Pass",
                  "Result"      => {"password" => "new_password"},
                  "ResultPath"  => "$.Credentials",
                  "Credentials" => {
                    "username.$" => "$.username",
                    "password.$" => "$.password"
                  },
                  "End"         => true
                }
              }
            }
          end

          it "replaces the mapped credential in the credentials hash" do
            workflow_instance.run

            expected_value = ManageIQ::Password.encrypt("new_password")
            expect(workflow_instance.reload.credentials).to include("password" => expected_value)
          end
        end
      end
    end
  end
end
