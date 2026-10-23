require_relative '../support/quiz_creator_native'
require_relative '../support/quiz_contributions'
require_relative '../../lib/quiz_contributions/controller'

NativeOptionTest.language = 'en'
module Session
  def self.name; 'guest'; end
end
Q = GameRoomQuizContributions
views = Object.new
views.define_singleton_method(:confirm) { |_message| true }
views.define_singleton_method(:notice) { |_message| }

[:delete, :submit, :persist].each do |operation|
  [false, true].each do |memory_only|
    Dir.mktmpdir('creator-recovery-branch-') do |directory|
      storage = QuestionContributionTest::Storage.new(directory)
      drafts = Q::Drafts.new(storage, user: 'guest', current_user: -> { Session.name })
      files = QuestionContributionTest::Files.new
      repository = Q::Repository.new(app_uuid: 'test', user: 'guest', current_user: -> { Session.name },
        client: Object.new, api: files)
      baseline = repository.save(QuestionContributionTest.sample.merge('snapshot' => SecureRandom.uuid))
      remote = repository.save(baseline.merge('description' => 'Another computer', 'snapshot' => SecureRandom.uuid))
      mailbox = QuestionContributionTest::Mailbox.new
      controller = Q::Controller.new(Object.new, repository: repository, drafts: drafts, views: views,
        delivery: Q::Delivery.new(repository, messages: mailbox))
      # Controller semantics only. Native task lifetime is tested separately.
      controller.define_singleton_method(:task) do |_title, **_options, &block|
        block.call(nil)
      rescue IOError
        nil
      end
      local = baseline.merge('description' => 'Unsent local work')
      storage.fail = memory_only
      files.fail = [:upload, false] unless memory_only
      local = controller.send(:persist, local)
      assert((memory_only ? controller.instance_variable_get(:@unsaved).values == [local] : drafts.list == [local]),
        'Failure fixture missed recovery')
      storage.fail = false
      case operation
      when :delete then controller.send(:delete_draft, repository.list.fetch(0))
      when :submit then controller.send(:submit, remote)
      when :persist then controller.send(:persist, remote.merge('description' => 'New remote edit'))
      end
      recovered = memory_only ? controller.instance_variable_get(:@unsaved).values : drafts.list
      assert(recovered.size == 1 && recovered.first == local,
        "#{operation} erased another #{memory_only ? 'memory' : 'disk'} recovery branch")
      assert(Q::Model.packet(recovered.first, author: 'guest') == Q::Model.packet(local, author: 'guest'),
        'Branch separation changed submission identity')
      assert(mailbox.rows.size == (operation == :submit ? 1 : 0), 'Unexpected submission count')
      # Acting on that exact recovery still cleans it, not every version of the set.
      controller.send(:delete_draft, local)
      assert(drafts.list.empty? && controller.instance_variable_get(:@unsaved).empty?, 'Exact branch cleanup failed')
    end
  end
end

Dir.mktmpdir('creator-multiple-recovery-') do |directory|
  storage = QuestionContributionTest::Storage.new(directory)
  drafts = Q::Drafts.new(storage, user: 'guest', current_user: -> { 'guest' })
  first = drafts.save(QuestionContributionTest.sample.merge('resource_id' => 1, 'resource_name' => 'first'))
  second = drafts.save(first.merge('resource_id' => 2, 'resource_name' => 'second', 'description' => 'Separate work'))
  assert(drafts.list == [first, second], 'Saving another branch overwrote the first recovery')
  assert(drafts.save(second) == second, 'Retry changed a branch snapshot')
  newer = drafts.save(first.merge('description' => 'New edits of first branch'))
  drafts.remove(first)
  assert(drafts.list == [newer, second], 'Stale cleanup deleted newer edits of the same branch')
  drafts.remove(second.reject { |key, _| %w[items snapshot].include?(key) })
  assert(drafts.list == [newer, second], 'Cloud metadata was sufficient to remove local edits')
  drafts.remove(second)
  assert(drafts.list == [newer], 'Deleting extra branch touched primary recovery')
  drafts.remove(newer)
  assert(drafts.list.empty?, 'Primary recovery was not cleaned')
end
puts "PASS creator recovery branches: #{$assertions} checks"
