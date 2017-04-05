require "psbot/logger"

module PSBot
  class Logger
    class FormattedLogger < Logger
      # @private
      Colors = {
        :reset    => "\e[0m",
        :bold     => "\e[1m",
        :red      => "\e[31m",
        :green    => "\e[32m",
        :yellow   => "\e[33m",
        :blue     => "\e[34m",
        :black    => "\e[30m",
        :bg_white => "\e[47m",
      }

      # (see Logger#exception)
      def exception(e)
        lines = ["#{e.backtrace.first}: #{e.message} (#{e.class})"]
        lines.concat e.backtrace[1..-1].map {|s| "\t" + s}
        log(lines, :exception, :error)
      end

      private
      def timestamp
        Time.now.strftime("[%Y/%m/%d %H:%M:%S.%L]")
      end

      # @api private
      # @param [String] text Text to colorize
      # @param [Array<Symbol>] codes Array of colors to apply
      # @return [String] colorized string
      def colorize(text, *codes)
        return text unless @output.tty?
        codes = Colors.values_at(*codes).join
        text = text.gsub(/#{Regexp.escape(Colors[:reset])}/, Colors[:reset] + codes)
        codes + text + Colors[:reset]
      end

      def format_general(message)
        # :print doesn't call all of :space: so use both.
        message.gsub(/[^[:print:][:space:]]/) do |m|
          colorize(m.inspect[1..-2], :bg_white, :black)
        end
      end

      def format_debug(message)
        "%s %s %s" % [timestamp, colorize("!!", :yellow), message]
      end

      def format_warn(message)
        format_debug(message)
      end

      def format_info(message)
        "%s %s %s" % [timestamp, "II", message]
      end

      # @note What you see from the console logger is NOT directly representative of
      # the message sent from the server. It is a stylistic representation of it for
      # your viewing pleasure.
      def format_incoming(message)
        room, rest = message.split("\n")
        return if rest.nil?
        parts = rest.split("|")
        prefix = colorize(">>", :green)

        if room.empty?
          # Format private messages
          parts = parts[1..-1]
          return "%s %s %s|%s" % [timestamp, prefix, colorize(parts[0], :blue), parts[1..-1].join("|")]
        end

        room = colorize(room[1..-1], :bold)

        if parts.empty?
          return "%s %s %s" % [timestamp, prefix, room]
        end

        if parts.length == 1
          # Format raw server messages
          return "%s %s %s|%s" % [timestamp, prefix, room, colorize(parts[0], :red)]
        end

        cmd = colorize(parts[1], :blue)
        params = parts[2..-1].join("|")

        "%s %s %s|%s|%s" % [timestamp, prefix, room, cmd, params]
      end

      def format_outgoing(message)
        room, rest = message.split("|")
        room = colorize(room, :bold)
        prefix = colorize("<<", :red)

        "%s %s %s|%s" % [timestamp, prefix, room, rest]
      end

      def format_exception(message)
        "%s %s %s" % [timestamp, colorize("!!", :red), message]
      end

      def format_error(message)
        format_exception(message)
      end
    end
  end
end
