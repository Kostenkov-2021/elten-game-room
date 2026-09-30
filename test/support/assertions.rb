module GameRoomTest
  module Assertions
    def assert(value, message = "Assertion failed")
      raise message unless value
    end

    def assert_equal(expected, actual, message = "Values differ")
      assert(expected == actual, "#{message}\nExpected: #{expected.inspect}\nActual: #{actual.inspect}")
    end

    def assert_raises(type)
      begin
        yield
      rescue type => error
        return error
      end
      raise "Expected #{type} to be raised"
    end
  end
end
