require_relative 'native_tasks'
require EltenTestHost.file('src/ui/loop.rb')
require EltenTestHost.file('src/eapi/core/runtime.rb')

# The peripheral fixtures replace loop_update. Invoke exactly the dispatch
# stage that 3.0.4 runs before controls/timers, with Core's real scene context.
module NativeSceneDispatch
  def native_scene_frame
    Object.new.extend(EltenAPI::UI).send(:dispatch_parallel_scene_events)
  end

  def within_native_scene(scene, &block)
    Object.new.extend(EltenAPI).send(:with_scene_context, scene, &block)
  end
end
