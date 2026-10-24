require_relative '../support/tournament_control_callbacks'
require_relative '../support/session_runner'
require_relative '../../lib/table_voice_screen'
include GameRoomTest::Assertions
GameRoomLocalization.boot(settings:{'interface_language'=>'en','known_languages'=>['en']})

class LocalConferenceDevice
  attr_reader :created, :joined, :leaves, :hooks
  attr_accessor :channel, :join_success, :muted, :push_to_talk, :auto_connect, :leave_success
  def initialize
    @created, @joined = [], []
    @hooks, @leaves = [], 0
    @auto_connect, @leave_success = true, true
    @join_success = true
    @muted, @push_to_talk = true, true
  end
  def opened?; !channel.nil?; end
  def on(event,&block); @hooks << [event,block]; @hooks.last; end
  def remove_hook(hook); @hooks.delete(hook); end
  def leave
    @leaves += 1
    @channel = Struct.new(:id).new(0) if leave_success
    leave_success
  end
  def create(*arguments)
    @created << arguments
    complete_creation if auto_connect
    246
  end
  def complete_creation
    person=Struct.new(:name).new(Session.name)
    @channel=Struct.new(:id,:name,:users).new(246,@created.last.first,[person])
    @hooks.each { |event,callback| callback.call if event==:update }
  end
  def join(id, password)
    @joined << [id,password]
    @channel = Struct.new(:id,:name).new(id,'Table conference') if join_success
    join_success
  end
end

def voice_program(notices, confirmations=[])
  Object.new.tap do |program|
    program.define_singleton_method(:run_network_task) { |*, **, &operation| operation.call }
    program.define_singleton_method(:alert) { |text| notices << text }
    program.define_singleton_method(:confirm) { |text| confirmations << text; true }
  end
end

def creation_step(driver, &before_create)
  driver.step('Channel name') do |form|
    form.fields[0].set_text('Table conference')
    form.fields[1].index=1
    form.fields[2].set_text('member-secret')
    before_create&.call
    form.fields.grep(Button).find { |button| button.label=='Create voice conversation' }.press
  end
end
