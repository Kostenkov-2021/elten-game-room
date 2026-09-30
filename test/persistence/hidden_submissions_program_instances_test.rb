require_relative "../../lib/hidden_submissions"
require 'timeout'

# Like ELTEN Program: all instances delegate to the same class-owned runtime.
class SharedHiddenProgram
  class << self
    def files; @files ||= {}; end
    def read_json(path, default: nil); Marshal.load(Marshal.dump(files.fetch(path, default))); end
    def write_json(path, value); files[path] = Marshal.load(Marshal.dump(value)); true; end
  end
  def read_json(*args, **options); self.class.read_json(*args, **options); end
  def write_json(*args); self.class.write_json(*args); end
end

stores = 2.times.map { HiddenSubmissions::ProgramStorage.new(SharedHiddenProgram.new) }
entered, release, second_entered = Queue.new, Queue.new, Queue.new
first = Thread.new do
  stores[0].update do |root|
    root['entries']['first'] = 1
    entered << true
    release.pop
  end
end
Timeout.timeout(2) { entered.pop }
second = Thread.new do
  stores[1].update { |root| second_entered << true; root['entries']['second'] = 2 }
end
begin
  sleep 0.05
  raise 'second Program instance entered the same file transaction' unless second_entered.empty?
ensure
  release << true
  Timeout.timeout(2) { first.value; second.value }
end
root = stores[0].read
raise 'one answer was lost' unless root['entries'] == {'first' => 1, 'second' => 2}
raise 'shared revision was not incremented twice' unless root['storage_revision'] == 2
other_path = HiddenSubmissions::ProgramStorage.new(SharedHiddenProgram.new, path: 'other.json')
other_path.update { |data| data['entries']['other'] = true }
raise 'distinct paths were mixed' unless stores[0].read == root
class OtherHiddenProgram < SharedHiddenProgram; end
other_program = HiddenSubmissions::ProgramStorage.new(OtherHiddenProgram.new)
raise 'another application inherited stored answers' unless other_program.read['entries'].empty?
puts 'PASS hidden submissions: two Program instances, serialized transactions, paths and applications isolated'
