require 'open3'
require 'rbconfig'

root = File.expand_path('..', __dir__)
cases = {
  'binary package reader' => <<~'RUBY',
    require_relative 'test/support/host_source'
    require_relative 'test/support/binary_rules_load'
    require 'tmpdir'
    class PackageBoundaryReached < StandardError; end
    module Zip
      class File
        def self.open(_path); raise PackageBoundaryReached; end
      end
    end
    $LOADED_FEATURES.concat(['zip.rb', 'zstd-ruby.rb'])
    Dir.mktmpdir('gr-host-contract-') do |directory|
      signing = File.join(directory, 'programsigning.rb')
      File.write(signing, '$test_host_signing_loaded = true')
      lookups = []
      EltenTestHost.define_singleton_method(:file) do |relative|
        lookups << relative
        signing
      end
      begin
        BinaryRulesLoad.package = 'not-an-installer.eltsetup'
        raise 'Package reader did not reach its boundary'
      rescue PackageBoundaryReached
      end
      raise "Package reader bypassed common host lookup: #{lookups.inspect}" unless
        lookups == ['src/eapi/programsigning.rb'] && $test_host_signing_loaded
    end
  RUBY
  'native presence SDK test' => <<~'RUBY'
    require_relative 'test/support/host_source'
    original = EltenTestHost.method(:file)
    lookups = []
    EltenTestHost.define_singleton_method(:file) do |relative|
      lookups << relative
      original.call(relative)
    end
    ENV['PRESENCE_CASE'] = 'real host Apps/AppTable offline transport'
    load 'test/room_presence_store_test.rb'
    raise 'Presence SDK test bypassed common host lookup' unless lookups == ['src/eltenlink/apps.rb']
  RUBY
}
failures = []
cases.each do |name, code|
  output, status = Open3.capture2e(RbConfig.ruby, '-e', code, chdir: root)
  if status.success?
    puts "PASS common host lookup: #{name}"
  else
    failures << "#{name}: #{output}"
  end
end
raise failures.join("\n") unless failures.empty?
