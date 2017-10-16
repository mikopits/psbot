require "time"
#require "psbot/formatting"

module PSBot
  # This class serves two purposes. For one, it simply
  # represents incoming messages and parses various details about
  # the message (who sent it, where it was sent from, etc.)
  #
  # At the same time, it allows **responding** to messages, which
  # means sending messages to either users or rooms.
  class Message
    # @return [String] the raw message from server
    attr_reader :raw

    # @return [String]
    attr_reader :prefix

    # @return [String] the command received
    attr_reader :command

    # @return [Array<String>]
    attr_reader :params

    # @return [Array<Symbol>]
    attr_reader :events
    # @api private
    attr_writer :events

    # @return [DateTime]
    attr_reader :time

    # @return [Bot]
    attr_reader :bot

    # @return [User, nil] the user who sent this message
    attr_reader :user

    # @return [String] the user's authority level
    attr_reader :auth

    # @return [String] the user's nickname, for convenience
    attr_reader :nick

    # @return [Array<String>] the parameters following a command
    attr_reader :params

    # @return [Room, nil] the room in which this message was sent
    attr_reader :room

    # @return [String, nil] the message sent
    attr_reader :message

    # Accessor to allow the target to be manually overwritten.
    # Use this if you want to forcefully private message even
    # on triggers in a room.
    #
    # @example
    #   m.target = m.user
    #   m.reply "private_message"
    #
    # @return [Target]
    attr_accessor :target

    # @return [Integer] the server time
    attr_reader :timestamp

    def initialize(msg, bot)
      @raw     = msg
      @bot     = bot
      @matches = {:other => {}}
      @events  = []
      @time    = DateTime.now
      if msg
        @nl_delimited = msg.split("\n")
        @vb_delimited = msg.split("|",-1)
        parse
      end
    end

    # @group Parsing

    # The raw messages come in the form with PARAMS separated
    # by vertical bars (|param1|param2|...).
    #
    # General (in room, and without room):
    # >ROOM\n|COMMAND|PARAMS
    # \n|COMMANDS|PARAMS
    #
    # Examples (from login to chat ready):
    # \n|updateuser|Guest XXXXX|0|1
    # \n|formats|,1|...|...|...|,2|...
    # \n|queryresponse|rooms|null
    # \n|challstr|2|...
    # \n|updateuser|shy imouto|1|265
    # >techcode\n|init|chat
    # >techcode\n|title|techcode
    # >techcode\n|users|20,#RO,@MOD,%DR,+VO1,+VO2,...
    # >techcode\n|:|TIMESTAMP
    # >techcode\n|c:|TIMESTAMP|+VO|ok
    #
    # @api private
    # @return [void]
    def parse
      @command   = parse_command || "none"
      @params    = parse_params
      @timestamp = parse_timestamp
      @room      = parse_room
      @user, @auth, @nick = parse_user
      @target    = parse_target
      @message   = parse_message
    end

    # If the message starts with a greater than sign (>) then
    # the message comes from a room.
    #
    # @api private
    # @return [Room, nil]
    def parse_room
      room = nil
      if @nl_delimited.first[0] == ">"
        room = @nl_delimited.first[1..-1]
      end
      return nil if room.nil?

      @bot.room_list.find_ensured(room)
    end

    # The command is always after the first vertical bar.
    #
    # @api private
    # @return [String]
    def parse_command
      return nil if @vb_delimited.length < 2

      @vb_delimited[1]
    end

    # Parse the parameters following a command.
    #
    # @note must be used after #parse_command
    # @api private
    # @return [Array<String>]
    def parse_params
      return nil unless @command
      return nil if @command == "none"

      @vb_delimited.drop(2)
    end

    # Parse the timestamp of a chat event.
    #
    # @note must be used after #parse_params
    # @api private
    # @return [Integer]
    def parse_timestamp
      return nil unless @command.downcase.include?(":")

      @params.first.to_i
    end

    # Parse the user sending a command.
    #
    # Short summary of user commands you might see.
    # @see docs#protocol for more detail
    #
    # chat/time => c:
    # chat      => c
    # join      => J
    # leave     => L
    # nick      => N
    # pm        => pm
    #
    # @api private
    # @note Must be used after #parse_command
    # @return [Array<[String, nil]>] user, auth, fullname
    def parse_user
      return nil unless @command
      auth = nil
      nick = nil

      case @command.downcase
      when "c:"
        auth = @vb_delimited[3][0]
        nick = @vb_delimited[3][1..-1]
      when "c", "j", "l", "n", "pm"
        auth = @vb_delimited[2][0]
        nick = @vb_delimited[2][1..-1]
      end

      return [nil, nil, nil] if nick.nil? || auth.nil?

      [@bot.user_list.find_ensured(nick), auth, nick]
    end

    # Parse the message sent by a user.
    #
    # @api private
    # @note must be used after #parse_command
    # @see options in #parse_user
    # @return [String, nil]
    def parse_message
      return nil unless @command
      message = nil

      case @command.downcase
      when "c:", "pm"
        message = @vb_delimited[4..-1].join("|")
      when "none"
        message = @nl_delimited.last
      end

      message
    end

    # Parse the target to reply to.
    #
    # @api private
    # @note must be used after #parse_command
    # @see options in #parse_user
    # @return [Room, User, nil]
    def parse_target
      return nil unless @command

      case @command.downcase
      when "pm"
        target = @user
      else
        target = @room
      end

      target
    end

    # @endgroup

    # @note at the moment typechecking is trivial but there are
    # practical applications in being able to discern the type
    # of message (bot can handle them differently).
    #
    # @api private
    # @return [MatchData]
    def match(regexp, type)
      text = message.to_s
      type = :other
      @matches[type][regexp] ||= text.match(regexp)
    end

    # @group Type checking

    # @endgroup

    # @group Replying

    # Replies to a message, automatically determining if it was a
    # room or a private message.
    #
    # @param [String] text the message
    # @option options [Boolean] :prefix (true) prefix if prefix is true
    #   and the message was in a room, the reply will be prefixed by the
    #   nickname of whoever sent the message
    # @option options [String] :prefix_before ("(") string to add before
    #   the prefix
    # @option options [String] :prefix_after (")") string to add after
    #   the prefix
    # @option options [Target, nil] :target (nil) override the target to
    #   send to. Does not override if nil
    # @option options [Boolean] :truncate (true) truncates the message
    #   being sent to the message character limit if true
    # @return [void]
    def reply(text, options = {})
      options = {
        prefix: true,
        prefix_before: "(",
        prefix_after: ")",
        target: nil,
        truncate: true,
      }.merge(options)

      @target = options[:target] if options[:target]
 
      text = "#{options[:prefix_before] + @user.nick + options[:prefix_after]} #{text.to_s}" if options[:prefix]

      if options[:truncate]
        msg = text[0..@bot.config.server_queue_size-1]
      else
        msg = text
      end
      @target.send(msg)
    end

    # @endgroup

    # @return [String]
    def to_s
      "#<PSBot::Message @raw=#{@raw.chomp.inspect} @params=#{@params.inspect} room=#{@room.inspect} user=#{@user.inspect}"
    end
  end
end
