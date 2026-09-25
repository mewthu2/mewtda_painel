require 'test_helper'

class Exchange::LookupThrottleTest < ActiveSupport::TestCase
  test 'allows requests under the limit' do
    throttle = Exchange::LookupThrottle.new(cache: ActiveSupport::Cache::MemoryStore.new)

    9.times { assert throttle.allow?('1.2.3.4') }
  end

  test 'blocks requests once the limit is exceeded' do
    throttle = Exchange::LookupThrottle.new(cache: ActiveSupport::Cache::MemoryStore.new)

    Exchange::LookupThrottle::LIMIT.times { throttle.allow?('1.2.3.4') }

    assert_not throttle.allow?('1.2.3.4')
  end

  test 'tracks different keys independently' do
    throttle = Exchange::LookupThrottle.new(cache: ActiveSupport::Cache::MemoryStore.new)

    Exchange::LookupThrottle::LIMIT.times { throttle.allow?('1.2.3.4') }

    assert throttle.allow?('5.6.7.8')
  end
end
