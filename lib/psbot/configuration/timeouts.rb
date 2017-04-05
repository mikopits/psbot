require "psbot/configuration"

module PSBot
  class Configuration
    class Timeouts < Configuration
      KnownOptions = [:read, :connect]

      def self.default_config
        {:read => 240, :connect => 10,}
      end
    end
  end
end
