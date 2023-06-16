RSpec.describe ManageIQ::Providers::Workflows::AutomationManager::Credential do
  let(:ems)  { FactoryBot.create(:ems_workflows_automation, :zone => zone) }
  let(:zone) { EvmSpecHelper.local_miq_server.zone }

  describe ".create" do
    it "fails to create a record without a name" do
      expect { described_class.create!(:resource => ems) }.to raise_error(ActiveRecord::RecordInvalid, /Ems ref can't be blank/)
    end

    it "doesn't allow records with duplicate names" do
      described_class.create!(:resource => ems, :ems_ref => "my-credential")
      expect { described_class.create!(:resource => ems, :ems_ref => "my-credential") }.to raise_error(ActiveRecord::RecordInvalid, /Ems ref has already been taken/)
    end

    it "doesn't allow records with invalid names" do
      expect { described_class.create!(:resource => ems, :ems_ref => "my credential") }.to raise_error(ActiveRecord::RecordInvalid, /Ems ref may contain only alphanumeric and _ - characters/)
      expect { described_class.create!(:resource => ems, :ems_ref => "my-credential.") }.to raise_error(ActiveRecord::RecordInvalid, /Ems ref may contain only alphanumeric and _ - characters/)
      expect { described_class.create!(:resource => ems, :ems_ref => "my%credential") }.to raise_error(ActiveRecord::RecordInvalid, /Ems ref may contain only alphanumeric and _ - characters/)
      expect { described_class.create!(:resource => ems, :ems_ref => "my$credential") }.to raise_error(ActiveRecord::RecordInvalid, /Ems ref may contain only alphanumeric and _ - characters/)
    end

    it "creates the authentication record" do
      record = described_class.create!(:resource => ems, :ems_ref => "my-credential")

      expect(record).to have_attributes(
        :ems_ref => "my-credential",
        :type    => "ManageIQ::Providers::Workflows::AutomationManager::Credential"
      )
    end
  end

  describe ".create_in_provider" do
    let(:params) { {"name" => "My Credential", "ems_ref" => "my-credential", "userid" => "admin", "password" => "1234"} }

    it "creates the credential with the requested params" do
      expect(described_class.create_in_provider(ems.id, params)).to have_attributes(
        :manager  => ems,
        :name     => params["name"],
        :ems_ref  => params["ems_ref"],
        :userid   => params["userid"],
        :password => params["password"]
      )
    end

    it "rejects parameters that aren't allowed" do
      expect { described_class.create_in_provider(ems.id, params.merge("resource" => "something nefarious")) }
        .to raise_error(ArgumentError, "Invalid parameters: resource")
    end
  end
end
