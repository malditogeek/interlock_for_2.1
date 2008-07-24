
module Interlock
  module Lock

    #
    # Try to acquire a global lock from memcached for a particular key.
    # If successful, yield and set the key to the return value, then release
    # the lock.
    #
    # Based on http://rubyurl.com/Sw7 , which I partially wrote.
    #

    def lock(key, lock_expiry = 30, retries = 5)
      retries.times do |count|

        # We have to be compatible with both client APIs. Eventually we can use Memcached#cas
        # for this.
        begin
          response = CACHE.add("lock:#{key}", "Locked by #{Process.pid}", lock_expiry)
          # Nil is a successful response for Memcached, so we'll simulate the MemCache
          # API.
          response ||= "STORED\r\n"
        rescue Object => e
          # Catch exceptions from Memcached without setting response.
        end

        if response == "STORED\r\n"
          begin
            value = yield(CACHE.get(key))
            CACHE.set(key, value)
            return value
          ensure
            CACHE.delete("lock:#{key}")
          end
        else
          sleep((2**count) / 2.0)
        end
      end
      raise ::Interlock::LockAcquisitionError, "Couldn't acquire lock for #{key}"
    end

  end
end
