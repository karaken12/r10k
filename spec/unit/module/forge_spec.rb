require 'r10k/module/forge'
require 'r10k/semver'
require 'spec_helper'

describe R10K::Module::Forge do

  include_context 'fail on execution'

  let(:fixture_modulepath) { File.expand_path('spec/fixtures/module/forge', PROJECT_ROOT) }
  let(:empty_modulepath) { File.expand_path('spec/fixtures/empty', PROJECT_ROOT) }

  describe "implementing the Puppetfile spec" do
    it "should implement 'branan/eight_hundred', '8.0.0'" do
      expect(described_class).to be_implement('branan/eight_hundred', '8.0.0')
    end

    it "should implement 'branan-eight_hundred', '8.0.0'" do
      expect(described_class).to be_implement('branan-eight_hundred', '8.0.0')
    end

    it "should fail with an invalid title" do
      expect(described_class).to_not be_implement('branan!eight_hundred', '8.0.0')
    end
  end

  describe "setting attributes" do
    subject { described_class.new('branan/eight_hundred', '/moduledir', '8.0.0') }

    it "sets the name" do
      expect(subject.name).to eq 'eight_hundred'
    end

    it "sets the author" do
      expect(subject.author).to eq 'branan'
    end

    it "sets the dirname" do
      expect(subject.dirname).to eq '/moduledir'
    end

    it "sets the title" do
      expect(subject.title).to eq 'branan/eight_hundred'
    end
  end

  describe "properties" do
    subject { described_class.new('branan/eight_hundred', fixture_modulepath, '8.0.0') }

    it "sets the module type to :forge" do
      expect(subject.properties).to include(:type => :forge)
    end

    it "sets the expected version" do
      expect(subject.properties).to include(:expected => '8.0.0')
    end

    it "sets the actual version" do
      expect(subject).to receive(:current_version).and_return('0.8.0')
      expect(subject.properties).to include(:actual => '0.8.0')
    end
  end

  describe '#expected_version' do
    it "returns an explicitly given expected version" do
      subject = described_class.new('branan/eight_hundred', fixture_modulepath, '8.0.0')
      expect(subject.expected_version).to eq '8.0.0'
    end

    it "uses the latest version from the forge when the version is :latest" do
      subject = described_class.new('branan/eight_hundred', fixture_modulepath, :latest)
      expect(subject.v3_module).to receive(:latest_version).and_return('8.8.8')
      expect(subject.expected_version).to eq '8.8.8'
    end

    it "uses the current version if it satisfies the condition" do
      subject = described_class.new('branan/eight_hundred', fixture_modulepath, '>= 8.0.0')
      expect(subject).to receive(:current_version).at_least(:once).and_return('8.1.0')
      expect(subject.expected_version).to eq '8.1.0'
    end

    it "uses the latest version from the forge that satisfies the conditions" do
      subject = described_class.new('branan/eight_hundred', fixture_modulepath, '>= 8.1.0')
      expect(subject).to receive(:current_version).at_least(:once).and_return('8.0.0')
      expect(subject.v3_module).to receive(:latest_version).at_least(:once).and_return('8.8.8')
      expect(subject.expected_version).to eq '8.8.8'
    end

    it "uses a lower version if there's an upper bound" do
      subject = described_class.new('branan/eight_hundred', fixture_modulepath, '>= 8.1.0 < 8.2.0')
      expect(subject).to receive(:current_version).at_least(:once).and_return('8.0.0')
#      expect(subject.v3_module).to receive(:latest_version).at_least(:once).and_return('8.8.8')
      expect(subject.v3_module).to receive(:versions).at_least(:once).and_return(['8.0.0','8.1.0', '8.1.1', '8.1.2', '8.2.0'])
      expect(subject.expected_version).to eq '8.1.2'
    end
  end

  describe 'determine the version spec' do
    it "gets the lower bound" do
      subject = described_class.new('branan/eight_hundred', fixture_modulepath, '>= 1.0.0')
      expect(subject.version_spec.lower_bound).to eq '1.0.0'
      expect(subject.version_spec.upper_bound).to eq nil
      expect(subject.version_spec.inc_lower_bound).to eq true
    end

    it "gets the lower bound (non inclusive)" do
      subject = described_class.new('branan/eight_hundred', fixture_modulepath, '> 1.0.0')
      expect(subject.version_spec.lower_bound).to eq '1.0.0'
      expect(subject.version_spec.upper_bound).to eq nil
      expect(subject.version_spec.inc_lower_bound).to eq false
    end

    it "gets the upper bound" do
      subject = described_class.new('branan/eight_hundred', fixture_modulepath, '<= 2.0.0')
      expect(subject.version_spec.lower_bound).to eq nil
      expect(subject.version_spec.upper_bound).to eq '2.0.0'
      expect(subject.version_spec.inc_upper_bound).to eq true
    end

    it "gets the upper bound (non inclusive)" do
      subject = described_class.new('branan/eight_hundred', fixture_modulepath, '< 2.0.0')
      expect(subject.version_spec.lower_bound).to eq nil
      expect(subject.version_spec.upper_bound).to eq '2.0.0'
      expect(subject.version_spec.inc_upper_bound).to eq false
    end

    it "still gets the bound with no spaces" do
      subject = described_class.new('branan/eight_hundred', fixture_modulepath, '>=1.0.0')
      expect(subject.version_spec.lower_bound).to eq '1.0.0'
      expect(subject.version_spec.upper_bound).to eq nil
      expect(subject.version_spec.inc_lower_bound).to eq true
    end

    it "gets a range" do
      subject = described_class.new('branan/eight_hundred', fixture_modulepath, '>= 1.0.0 < 2.0.0')
      expect(subject.version_spec.lower_bound).to eq '1.0.0'
      expect(subject.version_spec.upper_bound).to eq '2.0.0'
      expect(subject.version_spec.inc_lower_bound).to eq true
      expect(subject.version_spec.inc_upper_bound).to eq false
    end

    it "understands 1.x syntax" do
      subject = described_class.new('branan/eight_hundred', fixture_modulepath, '1.x')
      expect(subject.version_spec.lower_bound).to eq '1.0.0'
      expect(subject.version_spec.upper_bound).to eq '2.0.0'
      expect(subject.version_spec.inc_lower_bound).to eq true
      expect(subject.version_spec.inc_upper_bound).to eq false
    end

    it "understands 1.2.x syntax" do
      subject = described_class.new('branan/eight_hundred', fixture_modulepath, '1.2.x')
      expect(subject.version_spec.lower_bound).to eq '1.2.0'
      expect(subject.version_spec.upper_bound).to eq '1.3.0'
      expect(subject.version_spec.inc_lower_bound).to eq true
      expect(subject.version_spec.inc_upper_bound).to eq false
    end
  end

  describe "check version acceptability" do
    it "allows a version in the middle" do
      subject = described_class.new('branan/eight_hundred', fixture_modulepath, '1.x')
      expect(subject.version_in_range('1.1.0')).to eq true
    end

    it "does not allow a version outside the range" do
      subject = described_class.new('branan/eight_hundred', fixture_modulepath, '>= 1.1.0 < 2.0.0')
      expect(subject.version_in_range('1.0.5')).to eq false
      expect(subject.version_in_range('2.0.5')).to eq false
    end

    it "allows an exact match" do
      subject = described_class.new('branan/eight_hundred', fixture_modulepath, '>= 1.0.0 <= 2.0.0')
      expect(subject.version_in_range('1.0.0')).to eq true
      expect(subject.version_in_range('2.0.0')).to eq true
    end

    it "does not allow non-equal exact matches" do
      subject = described_class.new('branan/eight_hundred', fixture_modulepath, '> 1.0.0 < 2.0.0')
      expect(subject.version_in_range('1.0.0')).to eq false
      expect(subject.version_in_range('2.0.0')).to eq false
    end
  end

  describe "compare versions" do
    it "recognises equal versions" do
      expect(described_class::ForgeVersion.new('1.0.0') == described_class::ForgeVersion.new('1.0.0')).to eq true
    end

    it "major" do
      expect(described_class::ForgeVersion.new('1.6.6') < described_class::ForgeVersion.new('2.3.3')).to eq true
      expect(described_class::ForgeVersion.new('2.6.6') < described_class::ForgeVersion.new('1.3.3')).to eq false
    end

    it "minor" do
      expect(described_class::ForgeVersion.new('1.1.6') < described_class::ForgeVersion.new('1.2.3')).to eq true
      expect(described_class::ForgeVersion.new('1.2.6') < described_class::ForgeVersion.new('1.1.3')).to eq false
    end

    it "revision" do
      expect(described_class::ForgeVersion.new('1.1.1') < described_class::ForgeVersion.new('1.1.2')).to eq true
      expect(described_class::ForgeVersion.new('1.1.2') < described_class::ForgeVersion.new('1.1.1')).to eq false
    end
  end

  describe "determining the status" do

    subject { described_class.new('branan/eight_hundred', fixture_modulepath, '8.0.0') }

    it "is :absent if the module directory is absent" do
      allow(subject).to receive(:exist?).and_return false
      expect(subject.status).to eq :absent
    end

    it "is :mismatched if there is no module metadata" do
      allow(subject).to receive(:exist?).and_return true
      allow(File).to receive(:exist?).and_return false

      expect(subject.status).to eq :mismatched
    end

    it "is :mismatched if the metadata author doesn't match the expected author" do
      allow(subject).to receive(:exist?).and_return true

      allow(subject.metadata).to receive(:full_module_name).and_return 'blargh-blargh'

      expect(subject.status).to eq :mismatched
    end

    it "is :outdated if the metadata version doesn't match the expected version" do
      allow(subject).to receive(:exist?).and_return true

      allow(subject.metadata).to receive(:version).and_return '7.0.0'
      expect(subject.status).to eq :outdated
    end

    it "is :insync if the version and the author are in sync" do
      allow(subject).to receive(:exist?).and_return true

      expect(subject.status).to eq :insync
    end
  end

  describe "#sync" do
    subject { described_class.new('branan/eight_hundred', fixture_modulepath, '8.0.0') }

    it 'does nothing when the module is in sync' do
      allow(subject).to receive(:status).and_return :insync

      expect(subject).to receive(:install).never
      expect(subject).to receive(:upgrade).never
      expect(subject).to receive(:reinstall).never
      subject.sync
    end

    it 'reinstalls the module when it is mismatched' do
      allow(subject).to receive(:status).and_return :mismatched
      expect(subject).to receive(:reinstall)
      subject.sync
    end

    it 'upgrades the module when it is outdated' do
      allow(subject).to receive(:status).and_return :outdated
      expect(subject).to receive(:upgrade)
      subject.sync
    end

    it 'installs the module when it is absent' do
      allow(subject).to receive(:status).and_return :absent
      expect(subject).to receive(:install)
      subject.sync
    end
  end

  describe '#install' do
    it 'installs the module from the forge' do
      subject = described_class.new('branan/eight_hundred', fixture_modulepath, '8.0.0')
      release = instance_double('R10K::Forge::ModuleRelease')
      expect(R10K::Forge::ModuleRelease).to receive(:new).with('branan/eight_hundred', '8.0.0').and_return(release)
      expect(release).to receive(:install).with(subject.path)
      subject.install
    end
  end

  describe '#uninstall' do
    it 'removes the module path' do
      subject = described_class.new('branan/eight_hundred', fixture_modulepath, '8.0.0')
      expect(FileUtils).to receive(:rm_rf).with(subject.path.to_s)
      subject.uninstall
    end
  end

  describe '#reinstall' do
    it 'uninstalls and then installs the module' do
      subject = described_class.new('branan/eight_hundred', fixture_modulepath, '8.0.0')
      expect(subject).to receive(:uninstall)
      expect(subject).to receive(:install)
      subject.reinstall
    end
  end
end
