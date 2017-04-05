# -*- coding: utf-8 -*-
require "psbot/open_ended_queue"

module PSBot
  # Manages all outgoing messages, applying rate throttling
  # and fair distribution.
  #
  # @api private
  class MessageQueue
    def initialize(socket, bot)
      @socket               = socket
      @queues               = {:private => OpenEndedQueue.new, :generic => OpenEndedQueue.new}

      @queues_to_process    = Queue.new
      @queued_queues        = Set.new

      @mutex                = Mutex.new
      @time_since_last_send = nil
      @bot                  = bot

      @log = []
    end

    # @return [String]
    def inspect
      "#<MessageQueue @queues=#{@queues} @queues_to_process=#{@queues_to_process} @queued_queues=#{@queued_queues} @time_since_last_send=#{@time_since_last_send}>"
    end

    # Add messages that will be sent and displayed to the queue.
    # Outgoing messages are formatted as follows. Note that pms are
    # sent in the form of messages with the /pm command.
    #
    # [ROOM]|[REST]
    #
    # There are two ways to send messages, in a room and via pm.
    #
    # techcode|how do i code lol??
    # |/pm scotteh, party animal
    #
    # @param message [String] The raw message being sent to the socket.
    # @return [void]
    def queue(message)
      room, *rest = message.split("|")
      command = nil
      if rest[0] == "/" && rest[1] != "/"
        command, *params = rest.split(" ")
      end

      queue = nil
      case command
      when "/pm"
        @mutex.synchronize do
          queue = @queues[:private]
        end
      else
        queue = @queues[:generic]
      end
      queue << message

      @mutex.synchronize do
        unless @queued_queues.include?(queue)
          @queued_queues << queue
          @queues_to_process << queue
        end
      end
    end

    # @return [void]
    def process!
      while true
        wait

        queue = @queues_to_process.pop
        message = queue.pop.to_s.chomp

        if queue.empty?
          @mutex.synchronize do
            @queued_queues.delete(queue)
          end
        else
          @queues_to_process << queue
        end

        begin
          to_send = PSBot::Utilities::Encoding.encode_outgoing(message, @bot.config.encoding)
          @socket.send to_send
          @log << Time.now
          @bot.loggers.outgoing(message)

          @time_since_last_send = Time.now
        rescue IOError
          @bot.loggers.error "Could not send message (connectivity problems): #{message}"
        end
      end
    end

    private
    def wait
      mps            = @bot.config.messages_per_second
      max_queue_size = @bot.config.server_queue_size

      if @log.size > 1
        time_passed = 0

        @log.each_with_index do |one, index|
          second = @log[index+1]
          time_passed += second - one
          break if index == @log.size - 2
        end

        messages_processed = (time_passed * mps).floor
        effective_size = @log.size - messages_processed

        if effective_size <= 0
          @log.clear
        elsif effective_size >= max_queue_size
          sleep 1.0/mps
        end
      end
    end
  end
end
