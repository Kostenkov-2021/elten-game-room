require 'thread'

# The helper runs in the current application. Installed method bodies must be
# compiled at top level or explicitly rebound to the current observer. Host
# markers are stable across namespace reloads and never own a second wrapper.
module GameRoomHostBridge
  module_function

  def locate(target, marker:, method_name: nil, source: nil)
    ancestors = target.ancestors.take_while { |item| !item.equal?(target) }
    stored = target.instance_variable_get(marker)
    return stored if stored.is_a?(Module) && ancestors.include?(stored)
    return unless method_name && source
    ancestors.find do |candidate|
      next false unless candidate.instance_methods(false).include?(method_name)
      path = candidate.instance_method(method_name).source_location&.first.to_s.tr('\\', '/')
      path.end_with?(source)
    end
  end

  def prepare(target, marker:, method_name: nil, source: nil)
    bridge = locate(target, marker: marker, method_name: method_name, source: source) || Module.new
    target.prepend(bridge) unless target.ancestors.include?(bridge)
    target.instance_variable_set(marker, bridge)
    bridge
  end

  def registry(target, key:, lock:, initial:)
    mutex = target.instance_variable_get(lock) || Mutex.new
    target.instance_variable_set(lock, mutex)
    mutex.synchronize do
      entries = target.instance_variable_get(key)
      unless entries
        entries = initial
        target.instance_variable_set(key, entries)
      end
      yield entries
    end
  end
end
