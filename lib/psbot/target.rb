module PSBot
  # @since 1.0.0
  class Target
    include Comparable

    # @return [String]
    attr_reader :name

    # @return [Bot]
    attr_reader :bot

    def initialize(name, bot)
      @name = name
      @bot = bot
    end

    # Sends a message to the target. Assume that the text is already in
    # a format that the server expects depending of whether the Target
    # is an instance of User or Room.
    #
    # @param [#to_s] text The message to send
    # @return [void]
    def send(text)
      @bot.connection.send("#{text.to_s}")
    end
  end
end
