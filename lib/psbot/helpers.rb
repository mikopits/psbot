# -*- coding: utf-8 -*-
module PSBot
  # The Helpers module contains helpful methods for the
  # purpose of convenience and to make writing plugins easier
  # by hiding parts of the API.
  #
  # The Helpers module automatically gets included in all plugins.
  module Helpers

    AUTH_STRINGS = {"~" => "administrator",
                    "&" => "leader",
                    "#" => "roomowner",
                    "@" => "moderator",
                    "%" => "driver",
                    "★" => "battle participant",
                    "+" => "voiced user",
                    " " => "unvoiced user",
                    "?" => "muted user",
                    "‽" => "locker user",}

    # @group Logging

    # Automatically log exceptions to the loggers.
    #
    # @example
    #   def my_method
    #     rescue_exception do
    #       something_that_might_raise()
    #     end
    #   end
    #
    # @return [void]
    def rescue_exception
      begin
        yield
      rescue => e
        bot.loggers.exception(e)
      end
    end

    # (see Logger#log)
    def log(messages, event = :debug, level = event)
      if self.is_a?(PSBot::Plugin)
        messages = Array(messages).map {|m|
          "[#{self.class}] " + m
        }
      end
      @bot.loggers.log(messages, event, level)
    end

    # (see Logger#debug)
    def debug(message)
      log(message, :debug)
    end

    # (see Logger#error)
    def error(message)
      log(message, :error)
    end

    # (see Logger#fatal)
    def fatal(message)
      log(message, :fatal)
    end

    # (see Logger#info)
    def info(message)
      log(message, :info)
    end

    # (see Logger#warn)
    def warn(message)
      log(message, :warn)
    end

    # (see Logger#incoming)
    def incoming(message)
      log(message, :incoming, :log)
    end

    # (see Logger#outgoing)
    def outgoing(message)
      log(message, :outgoing, :log)
    end

    # (see Logger#exception)
    def exception(e)
      log(e.message, :exception, :error)
    end
    # @endgroup

    # @group Formatting
    # TODO: implement methods from PSBot::Formatting

    # (see .sanitize)
    def Sanitize(string)
      PSBot::Helpers.sanitize(string)
    end

    # Removes non-alphanumeric characters from a string. This is
    # particularly useful when it comes to identifying unique
    # usernames without ambiguity. Keep in mind that Pokemon Showdown
    # usernames are not case sensitive.
    #
    # TODO implement different levels of sanitization as well as
    #   banned string checking.
    def sanitize(string)
      string.downcase.gsub(/[^A-Za-z0-9]/, '')
    end

    # Splits a message into chunks of 300 characters or less as per
    # PS server's maximum character limit.
    #
    # @note there may be a better place to store the maximum character
    #   limit. As of now it does not look like the number will change
    #   but it could possibly be modified on custom servers. Perhaps
    #   in a server or network object that the Bot would store. You would
    #   then access it like @bot.server.character_limit
    #
    # @param [String] string The string to split
    # @return [Array<String>] The split string
    def message_split(string)
      string.scan(/.{1,300}/m)
    end

    # @endgroup

    # Send login information. Needed for Connection#on_challstr for
    # an asynchronous call to the server for login info.
    def self.login(name, pass, challengekeyid, challenge, &callback)
      EM::HttpRequest.new("https://play.pokemonshowdown.com/action.php").post(body: {
        'act' => 'login',
        'name' => name,
        'pass' => pass,
        'challengekeyid' => challengekeyid.to_i,
        'challenge' => challenge} ).callback { |http|
          callback.call(JSON.parse(http.response[1..-1])["assertion"])
        }
    end
  end
end
