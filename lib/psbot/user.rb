# -*- coding: utf-8 -*-
require "psbot/target"
require "timeout"

module PSBot
  # This class represents a user and includes methods to update user
  # information or to interact with them.
  class User < Target
    include PSBot::Helpers

    # For compatability. More natural to call user.nick
    def nick
      @name
    end

    # @return [String]
    attr_reader :name

    # @return [String]
    attr_reader :last_nick

    # @return [String] Unique representation of user
    attr_reader :id

    # @return [String] ID of last nick
    attr_reader :last_id

    def initialize(name, bot)
      @name = name
      @bot  = bot
      @id = sanitize(name)
    end

    # Send a message to this user.
    def send(text)
      super("|/pm #{@id}, #{text.to_s}")
    end

    # @return [String]
    def to_s
      @name
    end

    # @return [String]
    def inspect
      "#<User name=#{@name.inspect}>"
    end

    # Used to update the user's nick on nickchange events.
    #
    # @param [String] new_nick The user's new nick
    # @api private
    # @return [void]
    def update_nick(new_nick)
      @last_nick, @name = @name, new_nick
      @last_id, @id = @id, sanitize(new_nick)
      @bot.user_list.update_nick(self)
    end
  end
end
