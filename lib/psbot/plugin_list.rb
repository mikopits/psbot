module PSBot
  class PluginList < Array
    def initialize(bot)
      @bot = bot
      super()
    end

    # @param [Class<Plugin>] plugin
    def register_plugin(plugin)
      self << plugin.new(@bot)
    end

    # @param [Array<Class<Plugin>>] plugins
    def register_plugins(plugins)
      plugins.each { |plugin| register_plugin(plugin) }
    end

    def unregister_plugin(plugin)
      plugin.unregister
      delete(plugin)
    end

    def unregister_plugins(plugins)
      if plugins == self
        plugins = self.dup
      end
      plugins.each { |plugin| unregister_plugin(plugin) }
    end

    def unregister_all
      unregister_plugins(self)
    end
  end
end
