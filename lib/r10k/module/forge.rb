require 'r10k/module'
require 'r10k/errors'
require 'shared/puppet/module_tool/metadata'
require 'r10k/module/metadata_file'

require 'r10k/forge/module_release'
require 'shared/puppet_forge/v3/module'

require 'pathname'
require 'fileutils'

class R10K::Module::Forge < R10K::Module::Base

  R10K::Module.register(self)

  def self.implement?(name, args)
    !!(name.match %r[\w+[/-]\w+])
  end

  # @!attribute [r] metadata
  #   @api private
  #   @return [Puppet::ModuleTool::Metadata]
  attr_reader :metadata

  # @!attribute [r] v3_module
  #   @api private
  #   @return [PuppetForge::V3::Module] The Puppet Forge module metadata
  attr_reader :v3_module

  include R10K::Logging

  def initialize(title, dirname, expected_version)
    super
    @metadata_file = R10K::Module::MetadataFile.new(path + 'metadata.json')
    @metadata = @metadata_file.read

    @expected_version = expected_version || current_version || :latest
    @v3_module = PuppetForge::V3::Module.new(@title)
  end

  def sync(options = {})
    case status
    when :absent
      install
    when :outdated
      upgrade
    when :mismatched
      reinstall
    end
  end

  def properties
    {
      :expected => expected_version,
      :actual   => current_version,
      :type     => :forge,
    }
  end

  # @return [String] The expected version that the module
  def expected_version
    if @expected_version == :latest
      @expected_version = @v3_module.latest_version
    elsif !@expected_version.match('^\d+\.\d+\.\d+$')
      # Needs some processing doing
      @expected_version = get_matching_version()
    end
    @expected_version
  end

  # @return [String] A version that matches the version of the module
  def get_matching_version()
    # Before anything, check if the version spec is well defined.
    # If not, there's no point carrying on.
    if !version_spec then return nil end
    # First check if the current version works
    if current_version
      if version_in_range(current_version) then return current_version end
    end
    # Now try the latest version
    if version_in_range(@v3_module.latest_version) then return @v3_module.latest_version end
    # Otherwise run through all available versions to check, and use the latest
    best_match = nil
    for candidate in @v3_module.versions
      if (best_match == nil || ForgeVersion.new(best_match) < ForgeVersion.new(candidate)) && version_in_range(candidate)
        best_match = candidate
      end
    end
    return best_match
  end

  class ForgeVersion
    include Comparable

    attr :major
    attr :minor
    attr :revision

    def initialize(version_string)
      @version_string = version_string
      match = version_string.match('^ *(\d+)\.(\d+)\.(\d+) *$')
      @major = match[1].to_i
      @minor = match[2].to_i
      @revision = match[3].to_i
    end

    def to_s
      return "#{major}.#{minor}.#{revision}"
    end

    def <=>(other)
      compare = self.major <=> other.major
      if compare != 0 then return compare end
      compare = self.minor <=> other.minor
      if compare != 0 then return compare end
      return self.revision <=> other.revision
    end
  end

  def version_in_range(version_to_check)
    matches = true
    if version_spec.lower_bound
      if version_spec.inc_lower_bound
        comp = ForgeVersion.new(version_spec.lower_bound) <= ForgeVersion.new(version_to_check)
      else
        comp = ForgeVersion.new(version_spec.lower_bound) < ForgeVersion.new(version_to_check)
      end
      matches = (matches && comp)
    end
    if version_spec.upper_bound
      if version_spec.inc_upper_bound
        comp = ForgeVersion.new(version_spec.upper_bound) >= ForgeVersion.new(version_to_check)
      else
        comp = ForgeVersion.new(version_spec.upper_bound) > ForgeVersion.new(version_to_check)
      end
      matches = (matches && comp)
    end
    return matches
  end

  VersionSpec = Struct.new(:lower_bound, :upper_bound, :inc_lower_bound, :inc_upper_bound)

  def version_spec
    if not @version_spec
      if match = @expected_version.match('^ *(>=?|<=?) *(\d+\.\d+\.\d+) *$')
        if match[1] == '<'
          @version_spec = VersionSpec.new(nil, match[2], false, false)
        elsif match[1] == '<='
          @version_spec = VersionSpec.new(nil, match[2], false, true)
        elsif match[1] == '>'
          @version_spec = VersionSpec.new(match[2], nil, false, false)
        elsif match[1] == '>='
          @version_spec = VersionSpec.new(match[2], nil, true, false)
        end
      elsif match = @expected_version.match('^ *(>=?) *(\d+\.\d+\.\d+) +(<=?) *(\d+\.\d+\.\d+) *$')
        @version_spec = VersionSpec.new(match[2], match[4], match[1]=='>=', match[3]=='<=')
      elsif match = @expected_version.match('^ *((\d+)\.(\d+)\.x) *$')
        @version_spec = VersionSpec.new("#{match[2]}.#{match[3]}.0", "#{match[2]}.#{match[3].to_i+1}.0", true, false)
      elsif match = @expected_version.match('^ *((\d+)\.x) *$')
        @version_spec = VersionSpec.new("#{match[2]}.0.0", "#{match[2].to_i+1}.0.0", true, false)
      end
    end
    @version_spec
  end

  # @return [String] The version of the currently installed module
  def current_version
    @metadata ? @metadata.version : nil
  end

  alias version current_version

  def exist?
    path.exist?
  end

  def insync?
    status == :insync
  end

  # Determine the status of the forge module.
  #
  # @return [Symbol] :absent If the directory doesn't exist
  # @return [Symbol] :mismatched If the module is not a forge module, or
  #   isn't the right forge module
  # @return [Symbol] :outdated If the installed module is older than expected
  # @return [Symbol] :insync If the module is in the desired state
  def status
    if not self.exist?
      # The module is not installed
      return :absent
    elsif not File.exist?(@path + 'metadata.json')
      # The directory exists but doesn't have a metadata file; it probably
      # isn't a forge module.
      return :mismatched
    end

    # The module is present and has a metadata file, read the metadata to
    # determine the state of the module.
    @metadata_file.read(@path + 'metadata.json')

    if not @title.tr('/','-') == @metadata.full_module_name.tr('/','-')

      # This is a forge module but the installed module is a different author
      # than the expected author.
      return :mismatched
    end

    if expected_version && (expected_version != @metadata.version)
      return :outdated
    end

    return :insync
  end

  def install
    parent_path = @path.parent
    if !parent_path.exist?
      parent_path.mkpath
    end
    module_release = R10K::Forge::ModuleRelease.new(@title, expected_version)
    module_release.install(@path)
  end

  alias upgrade install

  def uninstall
    FileUtils.rm_rf full_path
  end

  def reinstall
    uninstall
    install
  end

  private

  # Override the base #parse_title to ensure we have a fully qualified name
  def parse_title(title)
    if (match = title.match(/\A(\w+)[-\/](\w+)\Z/))
      [match[1], match[2]]
    else
      raise ArgumentError, "Forge module names must match 'owner/modulename'"
    end
  end
end
