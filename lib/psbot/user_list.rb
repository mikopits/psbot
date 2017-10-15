require "psbot/cached_list"

module PSBot
  class UserList < CachedList
    include PSBot::Helpers

    # Finds or creates a user based on their nick.
    #
    # @param [String] nick The user's nick
    # @return [User]
    def find_ensured(nick)
      sanitized_nick = sanitize(nick)

      if sanitized_nick == @bot.id
        user = @bot
      end

      @mutex.synchronize do
        if user.nil?
          user = @cache[sanitized_nick] ||= User.new(nick, @bot)
        end
        user
      end
    end

    # Finds a user.
    #
    # @param [String] nick Nick of a user
    # @return [User, nil]
    def find(nick)
      sanitized_nick = sanitize(nick)

      if sanitized_nick == @bot.id
        return @bot
      end

      @mutex.synchronize do
        return @cache[sanitized_nick]
      end
    end

    # Update a user's name in the cache list
    #
    # @api private
    # @param [User]
    # @return [void]
    def update_nick(user)
      @mutex.synchronize do
        @cache.delete user.last_id
        @cache[user.id]
      end
    end

    # Remove a user from the cache.
    #
    # @api private
    # @param [User]
    # @return [void]
    def delete(user)
      @cache.delete_if {|n, u| u.id == user.id}
    end
  end
end
