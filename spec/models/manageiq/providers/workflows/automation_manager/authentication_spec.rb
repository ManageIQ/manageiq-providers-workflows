RSpec.describe ManageIQ::Providers::Workflows::AutomationManager::Authentication do
  let(:ems)  { FactoryBot.create(:ems_workflows_automation, :zone => zone) }
  let(:zone) { EvmSpecHelper.local_miq_server.zone }

  describe ".create" do
    it "fails to create a record without a name" do
      expect { described_class.create!(:resource => ems) }.to raise_error(ActiveRecord::RecordInvalid, /Name can't be blank/)
    end

    it "doesn't allow records with duplicate names" do
      described_class.create!(:resource => ems, :name => "my-credential")
      expect { described_class.create!(:resource => ems, :name => "my-credential") }.to raise_error(ActiveRecord::RecordInvalid, /Name has already been taken/)
    end

    it "doesn't allow records with invalid names" do
      expect { described_class.create!(:resource => ems, :name => "my credential") }.to raise_error(ActiveRecord::RecordInvalid, /Name may contain only alphanumeric and _ - characters/)
      expect { described_class.create!(:resource => ems, :name => "my-credential.") }.to raise_error(ActiveRecord::RecordInvalid, /Name may contain only alphanumeric and _ - characters/)
      expect { described_class.create!(:resource => ems, :name => "my%credential") }.to raise_error(ActiveRecord::RecordInvalid, /Name may contain only alphanumeric and _ - characters/)
      expect { described_class.create!(:resource => ems, :name => "my$credential") }.to raise_error(ActiveRecord::RecordInvalid, /Name may contain only alphanumeric and _ - characters/)
    end

    it "creates the authentication record" do
      record = described_class.create!(:resource => ems, :name => "my-credential")

      expect(record).to have_attributes(
        :name => "my-credential",
        :type => "ManageIQ::Providers::Workflows::AutomationManager::Authentication"
      )
    end
  end
end
