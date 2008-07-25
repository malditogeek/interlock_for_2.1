
module Interlock
  module Finders

    #
    # Cached find.
    #
    # Any other options besides ids short-circuit the cache.
    #
    def find(*args)
      args.pop if args.last.nil? or (args.last.is_a? Hash and !args.last.values.any?)
      return find_via_db(*args) if args.last.is_a? Hash or args.first.is_a? Symbol

      records = find_via_cache(args.flatten, true)

      if args.length > 1 or args.first.is_a? Array
        records
      else
        records.first
      end

    end

    #
    # Cached find_by_id. Short-circuiting works the same as find.
    #
    # Read the note on find_all_by_id
    def find_by_id(*args)
      #return method_missing(:find_by_id, *args) if args.last.is_a? Hash
      return if args.last.is_a? Hash
      find_via_cache(args, false).first
    end
    
    #
    # Cached find_all_by_id. Ultrasphinx uses this. Short-circuiting works the same as find.
    #
    # NOTE: This is pure shit, dude! I don't know exactly which is the behavior of the AR
    # method_missing but it seems like if you pass a find_all_by_id([3,2,1], {}), the last
    # Hash returns the (commented) method_missing and it rewrites the find_all_by_id method.
    # After that any find_all_by_id call behaves like an AR call shooting directly to the DB.
    # pompilio
    def find_all_by_id(*args)
      #return method_missing(:find_all_by_id, *args) if args.last.is_a? Hash
      return if args.last.is_a? Hash
      find_via_cache(args, false)
    end

    #
    # Build the model cache key for a particular id.
    #
    def caching_key(id)
      Interlock.caching_key(
        self.base_class.name,
        "find",
        id,
        "default"
      )
    end

    private

    def find_via_cache(ids, should_raise) #:doc:
      results = []

      ordered_keys_to_ids = ids.flatten.map { |id| [caching_key(id), id.to_i] }
      keys_to_ids = Hash[*ordered_keys_to_ids.flatten]

      records = {}

      if ActionController::Base.perform_caching
        load_from_local_cache(records, keys_to_ids)
        load_from_memcached(records, keys_to_ids)
      end

      load_from_db(records, keys_to_ids)

      # Put them in order

      ordered_keys_to_ids.each do |key, |
        record = records[key]
        raise ActiveRecord::RecordNotFound, "Couldn't find #{self.name} with ID=#{keys_to_ids[key]}" if should_raise and !record
        results << record
      end

      # Don't return Nil objects, only the found records
      results.compact
    end

    def load_from_local_cache(current, keys_to_ids) #:doc:
      # Load from the local cache
      records = {}
      keys_to_ids.each do |key, |
        record = Interlock.local_cache.read(key, nil)
        records[key] = record if record
      end
      current.merge!(records)
    end

    def load_from_memcached(current, keys_to_ids) #:doc:
      # Drop to memcached if necessary
      if current.size < keys_to_ids.size
        records = {}
        missed = keys_to_ids.reject { |key, | current[key] }

        records = CACHE.get_multi(*missed.keys)

        # Set missed to the caches
        records.each do |key, value|
          Interlock.say key, "is loading from memcached", "model"
          Interlock.local_cache.write(key, value, nil)
        end

        current.merge!(records)
      end
    end

    def load_from_db(current, keys_to_ids) #:doc:
      # Drop to db if necessary
      if current.size < keys_to_ids.size
        missed = keys_to_ids.reject { |key, | current[key] }
        ids_to_keys = keys_to_ids.invert

        # Load from the db
        
        # see the note on the find_all_by_id method
        #records = find_all_by_id(missed.values, {})
        
        records = find_via_db(:all, :conditions => {:id => missed.values})
        records = Hash[*(records.map do |record|
          [ids_to_keys[record.id], record]
        end.flatten)]

        # Set missed to the caches
        records.each do |key, value|
          Interlock.say key, "is loading from the db", "model"
          Interlock.local_cache.write(key, value, nil)
          CACHE.set key, value unless Interlock.config[:disabled]
        end

        current.merge!(records)
      end
    end

  end
end
