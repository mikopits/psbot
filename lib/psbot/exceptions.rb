module PSBot
  # A collection of exceptions.
  module Exceptions
    # Generic error. Superclass for all PSBot-specific errors.
    class Generic < ::StandardError
    end

    # Generic error when an argument is too long.
    class ArgumentTooLong < Generic
    end

    # Error that is raised when a nick is too long to be used
    class NickTooLong < ArgumentTooLong
    end

    # Error that is raised when a kick reasong is too long.
    class KickReasonTooLong < ArgumentTooLong
    end

    # Raised whenever PSBot discovers a features it doesn't
    # support yet.
    class UnsupportedFeature < Generic
    end

    # Raised when a synced attribute hasn't been available for too
    # long.
    class SyncedAttributeNotAvailable < Generic
    end
  end
end
