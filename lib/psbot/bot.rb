# -*- coding: utf-8 -*-
require "faye/websocket"
require "em-http-request"
require "eventmachine"
require "socket"
require "thread"
require "ostruct"
require "json"

require "psbot/rubyext/module"
require "psbot/rubyext/float"

require "psbot/exceptions"

require "psbot/handler"
require "psbot/helpers"

require "psbot/logger_list"
require "psbot/logger"

require "psbot/logger/formatted_logger"
require "psbot/message"
require "psbot/message_queue"
require "psbot/connection"
require "psbot/target"
require "psbot/room"
require "psbot/user"
require "psbot/callback"
require "psbot/plugin"
require "psbot/pattern"

require "psbot/handler_list"
require "psbot/cached_list"
require "psbot/room_list"
require "psbot/user_list"
require "psbot/plugin_list"

require "psbot/timer"

require "psbot/configuration"
require "psbot/configuration/bot"
require "psbot/configuration/plugins"
require "psbot/configuration/timeouts"

module PSBot
  # @attr nick
  class Bot < User
    include Helpers

    # @return [Configuration::Bot]
    # @version 1.0
    attr_reader :config

    # The web socket connection.
    #
    # @return [Connection]
    attr_reader :connection

    # The logger list containing all loggers.
    #
    # @return [LoggerList]
    attr_accessor :loggers

    # @return [Array<Room>] All rooms the bot currently is in
    attr_reader :rooms

    # @return [PluginList] The {PluginList} giving access to
    #   (un)loading plugins
    attr_reader :plugins

    # @return [Boolean] whether the bot is in the process of disconnecting
    attr_reader :quitting

    # @return [UserList] All {User users} the bot knows about.
    # @see UserList
    attr_reader :user_list

    # @return [RoomList] All {Room rooms} the bot knows about.
    # @see RoomList
    attr_reader :room_list

    # @return [Boolean]
    # @api private
    attr_accessor :last_connection_was_successful

    # @return [Callback]
    # @api private
    attr_reader :callback

    # The {HandlerList}, providing access to all registered plugins
    # and plugin manipulation as well as {HandlerList#dispatch calling handlers}.
    #
    # @return [HandlerList]
    # @see HandlerList
    attr_reader :handlers

    # @group Helper methods

    # Define helper methods in the context of the bot.
    #
    # @yield Expects a block containing method definitions
    # @return [void]
    def helpers(&b)
      @callback.instance_eval(&b)
    end

    # Since PSBot uses threads, all handlers can be run
    # simultaneously, even the same handler multiple times. This also
    # means, that your code has to be thread-safe. Most of the time,
    # this is not a problem, but if you are accessing stored data, you
    # will most likely have to synchronize access to it. Instead of
    # managing all mutexes yourself, PSBot provides a synchronize
    # method, which takes a name and block.
    #
    # Synchronize blocks with the same name share the same mutex,
    # which means that only one of them will be executed at a time.
    #
    # @param [String, Symbol] name A name for the synchronize block.
    # @return [void]
    #
    # @example
    #   configure do |c|
    #     ...
    #     @i = 0
    #   end
    #
    #   on :channel, /^start counting!/ do
    #     synchronize(:my_counter) do
    #       10.times do
    #         val = @i
    #         # at this point, another thread might've incremented :i already.
    #         # this thread wouldn't know about it, though.
    #         @i = val + 1
    #       end
    #     end
    #   end
    def synchronize(name, &block)
      # Must run the default block +/ fetch in a thread safe way in order to
      # ensure we always get the same mutex for a given name.
      semaphore = @semaphores_mutex.synchronize { @semaphores[name] }
      semaphore.synchronize(&block)
    end

    # @endgroup

    # @group Events &amp; Plugins

    # Registers a handler.
    #
    # @param [String, Symbol, Integer] event the event to match. For a
    #   list of available events, check the {file:docs/events.md Events
    #   documentation}.
    #
    # @param [Regexp, Pattern, String] regexp every message of the
    #   right event will be checked against this argument and the event
    #   will only be called if it matches.
    #
    # @param [Array<Object>] args Arguments that should be passed to
    #   the block, additionally to capture groups of the regexp.
    #
    # @yieldparam [Array<String>] args Each capture groupd of the regex will
    #   be one argument to the block.
    #
    # @return [Handler] The handlers that have been registered
    def on(event, regexp = //, *args, &block)
      event = event.to_s.to_sym

      pattern = case regexp
                when Pattern
                  regexp
                when Regexp
                  Pattern.new(nil, regexp, nil)
                else
                  Pattern.new(/^/, /#{Regexp.escape(regexp.to_s)}/, /$/)
                end

      handler = Handler.new(self, event, pattern, {args: args, execute_in_callback: true}, &block)
      @handlers.register(handler)

      return handler
    end

    # @endgroup
    # @group Bot Control

    # This method is used to set a bot's options. It indeed does
    # nothing else but yielding {Bot#config}, but it makes for a nice DSL.
    #
    # @yieldparam [Struct] config The bot's config
    # @return [void]
    def configure
      yield @config
    end

    # Disconnects from the server.
    #
    # @param [String] message The quit message to send while quitting.
    # @return [void]
    def quit(message = nil)
      @quitting = true
      @rooms.each do |room|
        @connection.send "#{room.to_s}|#{message}" if message
        @connection.send "|/leave #{room.to_s}"
      end
      @connection.send "|/logout"
    end

    # Connects the bot to a server.
    #
    # @param [Boolean] plugins Automatically register plugins from
    #   `@config.plugins.plugins`?
    # @return [void]
    def start(plugins = true)
      @reconnects = 0
      @plugins.register_plugins(@config.plugins.plugins) if plugins

      begin
        @rooms = [] # reset list of rooms the bot is in

        @join_handler.unregister if @join_handler
        @join_timer.stop if @join_timer

        join_lambda = lambda { @config.rooms.each {|room| @room_list.find_ensured(room).join}}

        if @config.delay_joins.is_a?(Symbol)
          @join_handler = join_handler = on(@config.delay_joins) {
            join_handler.unregister
            join_lambda.call
          }
        else
          @join_timer = Timer.new(self, interval: @config.delay_joins, shots: 1) {
            join_lambda.call
          }
        end

        @loggers.info "Connecting to #{@config.server}:#{@config.port}..."

        EM.run {
          @connection = Connection.new(self)
          @connection.connect
        }

        if @config.reconnect && !@quitting
          # double the delay for each unsuccessful reconnection attempt
          if @last_connection_was_successful
            @reconnects = 0
            @last_connection_was_successful = false
          else
            @reconnects += 1
          end

          # Throttle reconnect attempts
          wait = 2**@reconnects
          wait = @config.max_reconnect_delay if wait > @config.max_reconnect_delay
          @loggers.info "Waiting #{wait} seconds before reconnecting"
          start_time = Time.now
          while !@quitting && (Time.now - start_time) < wait
            sleep 1
          end
        end
      end while @config.reconnect and not @quitting
    end

    # @endgroup
    # @group Room Control

    # Join a room.
    #
    # @param [String, Room] room Either the name of a room or a {Room} object
    # @return [Room] The joined room
    # @see Room#join
    def join(room)
      room = @room_list.find_ensured(room)
      room.join
      @rooms << room

      room
    end

    # Leave a room.
    #
    # @param [String, Room] room Either the name of a room or a {Room} object
    # @param [String] reason An optional reason/part message
    # @return [Room] The room that was left
    # @see Room#leave
    def leave(room, reason = nil)
      room = @room_list.find_ensured(room)
      room.leave(reason)
      @rooms.delete(room)

      room
    end

    # @endgroup

    # @yield
    def initialize(&b)
      @loggers = LoggerList.new
      @loggers << Logger::FormattedLogger.new($stderr)

      @config           = Configuration::Bot.new
      @handlers         = HandlerList.new
      @semaphores_mutex = Mutex.new
      @semaphores       = Hash.new { |h, k| h[k] = Mutex.new }
      @callback         = Callback.new(self)
      @rooms            = []
      @quitting         = false

      @user_list = UserList.new(self)
      @room_list = RoomList.new(self)
      @plugins   = PluginList.new(self)

      @join_handler = nil
      @join_timer   = nil

      super(@config.nick, self)
      instance_eval(&b) if block_given?
    end

    # @return [self]
    # @api private
    def bot
      # This method is needed for the Helpers interface
      self
    end

    # Used for updating the bot's nick from within the Connection parser.
    #
    # @param [String] nick
    # @api private
    # @return [String]
    def set_nick(nick)
      @name = nick
    end

    # The bot's nickname.
    # @overload nick=(new_nick)
    #   @raise [Exceptions::NickTooLong] Raised if the bot is
    #     operating in {#strict? strict mode) and the new nickname is
    #     too long
    #   @return [String]
    # @overload nick
    #   @return [String]
    # @return [String]
    def nick
      @name
    end

    def nick=(new_nick)
      if new_nick.size > 18 && strict?
        raise Exceptions::NickTooLong, new_nick
      end
      @config.nick = new_nick
      @connection.send "|/nick #{new_nick}"
      # TODO: deal with name taken / passwords and such
      # or, just get rid of this entirely
    end

    # @return [String]
    def inspect
      "#<Bot nick=#{@name.inspect}>"
    end
  end
end
