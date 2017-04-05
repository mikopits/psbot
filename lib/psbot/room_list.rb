require "psbot/cached_list"

module PSBot
  class RoomList < CachedList

    # Finds a room or creates it if it is not cached.
    #
    # @param [String] name Name of a room
    # @return [Room]
    # @see Helpers#Room
    def find_ensured(name)
      @mutex.synchronize do
        @cache[name] ||= Room.new(name, @bot)
      end
    end

    # Finds a room.
    #
    # @param [String] name Name of a room
    # @return [Room, nil]
    def find(name)
      @cache[name]
    end
  end
end
