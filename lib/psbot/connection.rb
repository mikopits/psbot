module PSBot
  # This class manages the connection to the Showdown server. That
  # includes processes incoming and outgoing messages, creating Ruby
  # objects and invoking plugins.
  class Connection
    include Helpers
    include EM::Deferrable

    # @return [Bot]
    attr_reader :bot

    # @return [Boolean]
    attr_reader :connected

    def initialize(bot)
      @bot = bot
      @throttle = 1
      @max_throttle = 8
      @connected = false
    end

    # @return [Faye::WebSocket::Client]
    # @api private
    attr_reader :socket

    # @api private
    # @return [void]
    def setup
      if !@connected
        @reading_thread = start_reading_thread
        @sending_thread = start_sending_thread
        @reading_thread.join
      end
      @login_time = nil
    end

    # Establish a connection
    #
    # @api private
    # @return [Boolean] True if the connection was successful
    def connect
      @socket = nil
      url = "ws://#{@bot.config.server}:#{@bot.config.port}/showdown/websocket"
      @bot.loggers.info "Connecting to the websocket at #{url}..."
      @socket = Faye::WebSocket::Client.new(url)
      @queue = MessageQueue.new(@socket, @bot)

      @socket.on :open do |event|
        setup
        @bot.loggers.info "Connection to the server #{@bot.config.server} successful"
        @connected = true
        @throttle = 1
        @bot.last_connection_was_successful = true
      end

      @socket.on :close do |event|
        warn "Failed to connect to the server #{@bot.config.server}. Waiting #{@throttle} seconds before next attempt."
        @connected = false
        sleep @throttle
        @throttle = @throttle*2 >= @max_throttle ? @max_throttle : @throttle*2
        @throttle *= 2
        connect
      end
    end

    # @api private
    # @return [Thread] the reading thread
    def start_reading_thread
      Thread.new do
        begin
          @socket.on :message do |event|
            rescue_exception do
              messages = event.data.split("\n")
              if messages[0][0] == ">"
                room = messages.shift
              end

              messages.each do |rawmessage|
                message = "#{room}\n#{rawmessage}"
                parse PSBot::Utilities::Encoding.encode_incoming(message, @bot.config.encoding)
              end
            end
          end

          @socket.on :close do |event|
            @bot.loggers.warn "Socket connection closed. code=#{event.code}"
            @connected = false
            connect
          end
        rescue => e
          @bot.loggers.exception(e)
          raise e
        end
      end
    end

    # @api private
    # @return [Thread] the sending thread
    def start_sending_thread
      Thread.new do
        rescue_exception do
          @queue.process!
        end
      end
    end

    # @api private
    # @return [void]
    def parse(input)
      return if input.chomp.empty?

      msg    = Message.new(input, @bot)
      events = [[:catchall]]

      @bot.loggers.incoming(input) unless msg.command == "debug"

      case msg.command.downcase
      when ":"
        @login_time = msg.timestamp
      when "updateuser"
        events << [:connect] if msg.params[1] == "1"
      when "c"
        events << [:message] if msg.params.first != "~"
      end

      meth = "on_#{msg.command.downcase}".gsub(/c:/, "chat")
      __send__(meth, msg, events) if respond_to?(meth, true)

      events << [msg.command.downcase.to_sym]

      msg.events = events.map(&:first)
      events.each do |event, *args|
        @bot.handlers.dispatch(event, msg, *args)
      end
    end

    # @group Message handling

    def on_challstr(msg, events)
      # Send asynchronous login request.
      # TODO: What happens if the request fails?
      @bot.loggers.info "Attempting to log in..."
      PSBot::Helpers.login(@bot.config.nick, @bot.config.password, msg.params.first, msg.params.last) do |assertion|
        @bot.loggers.warn "Failed to receive login info." if assertion.nil?
        if assertion
          @bot.set_nick(@bot.config.nick)
          send "|/trn #{@bot.nick},0,#{assertion}"
        end
      end
    end

    def on_updateuser(msg, events)
      case msg.params[1]
      when "0" # Guest
        send "|/avatar #{@bot.config.avatar}" if @bot.config.avatar && !@avatar_set
        @avatar_set = true
      when "1" # Logged in
        @bot.config.rooms.each do |room|
          @bot.join(room)
        end
      end
    end

    def on_l(msg, events)
      msg.room.remove_user(msg.user)

      if msg.user == @bot
        @bot.rooms.delete msg.room if @bot.rooms.include?(msg.room)
      end
    end

    def on_j(msg, events)
      msg.room.add_user(msg.user, msg.auth)

      if msg.user == @bot
        on_init(msg, events)
      end
    end

    def on_n(msg, events)
      if msg.user == @bot
        target = @bot
      else
        target = msg.user
      end
      msg.room.remove_user(target)
      target.update_nick(msg.user.nick)
      bot.user_list.update_nick(target)
      msg.room.add_user(msg.user, msg.auth)
    end

    def on_init(msg, events)
      # This may occur if the bot is redirected. Leave the room if it
      # is not a room it should be in, and try to rejoin any rooms that
      # it should be in.
      #
      # Note that a successful /join will trigger another init event.
      # So be careful to not cause an infinite loop.
      if !@bot.config.rooms.include?(msg.room.name) && @bot.config.leave_other_rooms
        @bot.leave(msg.room.name)
        # Try to join each of the config rooms, as you may have been redirected.
        # It is safe to call "/join [room]" if you are already in it so there is
        # not really a need to check.
        @bot.config.rooms.each do |room_name|
          @bot.room_list.find_ensured(room_name).join
        end
      end
    end

    def on_deinit(msg, events)
      msg.room.remove_user(@bot)
      @bot.rooms.delete(msg.room)
    end

    def on_users(msg, events)
      # Populate the room with its users
      msg.params[0].split(",").drop(1).each do |user|
        auth = user[0]
        nick = user[1..-1]
        msg.room.add_user(@bot.user_list.find_ensured(nick), auth)
      end
    end

    # Getting unbanned from a room will trigger a rejoin if that particular room
    # is in @bot.config.rooms
    def on_popup(msg, events)
      # Handle bans
      if msg.params[2].include?("has banned you from the room")
        user, room = msg.params[2].match(/(.*) has banned you from the room (.*)\.<\/p><p>To appeal the ban/)[1,2]
        @bot.loggers.warn "You have been banned from the room #{room} by user #{user}"
        # TODO: This is a lazy solution, but the server no longer notifies you if you are unbanned.
        # Try to rejoin once after a potential kick
        sleep(1)
        @bot.room_list.find(room).join
      end
    end

    # Chatroom events
    # @note The command for chat is "c:" but we replace it for the sake
    # of this method name.
    def on_chat(msg, events)
      return unless @login_time
      events << [:message] if msg.message && msg.timestamp >= @login_time
    end

    # Private message events
    def on_pm(msg, events)
      events << [:private]
      events << [:message] if msg.message
    end

    def on_tournament(msg, events)
      param = msg.params.first
      # Tournaments are very noisy and send a lot of information we don't need, so we
      # only want to listen to tournament create, update, and start events. You can
      # still use the :tournament symbol for all tournament events.
      events << [:tour] if param == "create" || param == "update" || param == "start"
    end

    def on_queryresponse(msg, events)
      # Populate the bot with "roomlist" information.
      if msg.params[0] == "roomlist"
        @bot.battle_list = JSON.parse(msg.params[1])["rooms"]
      end
    end
    # @endgroup

    # Send a message to the server.
    # @param [String] msg
    # @return [void]
    def send(msg)
      @queue.queue(msg)
    end
  end
end
