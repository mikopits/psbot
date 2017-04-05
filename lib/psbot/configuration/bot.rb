require "psbot/configuration"

module PSBot
  class Configuration
    class Bot < Configuration
      KnownOptions = [:server, :port, :password, :nick, :messages_per_second,
                      :server_queue_size, :message_split_start, :message_split_end,
                      :max_messages, :plugins, :rooms, :encoding, :reconnect,
                      :max_reconnect_delay, :local_host, :timeouts, :delay_joins,
                      :shared, :avatar, :leave_other_rooms]

      # (see Configuration.default_config)
      def self.default_config
        {
          :server => "sim.smogon.com",
          :port => 8000,
          :password => nil,
          :nick => "psbot",
          :messages_per_second => 3,
          :server_queue_size => 300,
          :message_split_start => '... ',
          :message_split_end   => ' ...',
          :max_messages => nil,
          :plugins => Configuration::Plugins.new,
          :rooms => [],
          :encoding => :utf,
          :reconnect => true,
          :max_reconnect_delay => 8,
          :local_host => nil,
          :timeouts => Configuration::Timeouts.new,
          :delay_joins => 0,
          :shared => {},
          :avatar => nil,
          :leave_other_rooms => true,
        }
      end
    end
  end
end
