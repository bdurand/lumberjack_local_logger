# frozen_string_literal: true

require "lumberjack"

# Instantiate a lightweight logger that proxies logging calls to a parent logger but
# which can have its own distinct logging level, progname, and tags.
#
# This allows for implementing a pattern where different parts of an application can have
# their own loggers that can add metadata or change the logging level without having to
# create entirely separate logger instances.
class Lumberjack::LocalLogger
  attr_reader :parent_logger

  def initialize(parent_logger, level: nil, progname: nil, tags: nil)
    @parent_logger = parent_logger
    @local_level = Lumberjack::Severity.coerce(level) unless level.nil?
    @local_progname = progname
    @local_tags = tags
  end

  def level
    Thread.current[:lumberjack_local_logger_level] || @local_level || @parent_logger.level
  end

  def level=(severity)
    @local_level = Lumberjack::Severity.coerce(severity)
  end

  def with_level(temporary_level, &block)
    save_level = Thread.current[:lumberjack_local_logger_level]
    begin
      Thread.current[:lumberjack_local_logger_level] = temporary_level
      @parent_logger.with_level(temporary_level, &block)
    ensure
      Thread.current[:lumberjack_local_logger_level] = save_level
    end
  end

  alias_method :log_at, :with_level

  def silence(temporary_level = Logger::ERROR, &block)
    with_level(temporary_level, &block)
  end

  # Log a +FATAL+ message. The message can be passed in either the +message+ argument or in a block.
  #
  # @param [Object] message_or_progname_or_tags The message to log or progname
  #   if the message is passed in a block.
  # @param [String, Hash] progname_or_tags The name of the program that is logging the message or tags
  #   if the message is passed in a block.
  # @return [void]
  def fatal(message_or_progname_or_tags = nil, progname_or_tags = nil, &block)
    call_with_local_overrides do
      @parent_logger.fatal(message_or_progname_or_tags, progname_or_tags, &block)
    end
  end

  # Return +true+ if +FATAL+ messages are being logged.
  #
  # @return [Boolean]
  def fatal?
    level <= Logger::FATAL
  end

  # Set the log level to fatal.
  #
  # @return [void]
  def fatal!
    self.level = Logger::FATAL
  end

  # Log an +ERROR+ message. The message can be passed in either the +message+ argument or in a block.
  #
  # @param [Object] message_or_progname_or_tags The message to log or progname
  #   if the message is passed in a block.
  # @param [String, Hash] progname_or_tags The name of the program that is logging the message or tags
  #   if the message is passed in a block.
  # @return [void]
  def error(message_or_progname_or_tags = nil, progname_or_tags = nil, &block)
    call_with_local_overrides do
      @parent_logger.error(message_or_progname_or_tags, progname_or_tags, &block)
    end
  end

  # Return +true+ if +ERROR+ messages are being logged.
  #
  # @return [Boolean]
  def error?
    level <= Logger::ERROR
  end

  # Set the log level to error.
  #
  # @return [void]
  def error!
    self.level = Logger::ERROR
  end

  # Log a +WARN+ message. The message can be passed in either the +message+ argument or in a block.
  #
  # @param [Object] message_or_progname_or_tags The message to log or progname
  #   if the message is passed in a block.
  # @param [String, Hash] progname_or_tags The name of the program that is logging the message or tags
  #   if the message is passed in a block.
  # @return [void]
  def warn(message_or_progname_or_tags = nil, progname_or_tags = nil, &block)
    call_with_local_overrides do
      @parent_logger.warn(message_or_progname_or_tags, progname_or_tags, &block)
    end
  end

  # Return +true+ if +WARN+ messages are being logged.
  #
  # @return [Boolean]
  def warn?
    level <= Logger::WARN
  end

  # Set the log level to warn.
  #
  # @return [void]
  def warn!
    self.level = Logger::WARN
  end

  # Log an +INFO+ message. The message can be passed in either the +message+ argument or in a block.
  #
  # @param [Object] message_or_progname_or_tags The message to log or progname
  #   if the message is passed in a block.
  # @param [String] progname_or_tags The name of the program that is logging the message or tags
  #   if the message is passed in a block.
  # @return [void]
  def info(message_or_progname_or_tags = nil, progname_or_tags = nil, &block)
    call_with_local_overrides do
      @parent_logger.info(message_or_progname_or_tags, progname_or_tags, &block)
    end
  end

  # Return +true+ if +INFO+ messages are being logged.
  #
  # @return [Boolean]
  def info?
    level <= Logger::INFO
  end

  # Set the log level to info.
  #
  # @return [void]
  def info!
    self.level = Logger::INFO
  end

  # Log a +DEBUG+ message. The message can be passed in either the +message+ argument or in a block.
  #
  # @param [Object] message_or_progname_or_tags The message to log or progname
  #   if the message is passed in a block.
  # @param [String, Hash] progname_or_tags The name of the program that is logging the message or tags
  #   if the message is passed in a block.
  # @return [void]
  def debug(message_or_progname_or_tags = nil, progname_or_tags = nil, &block)
    call_with_local_overrides do
      @parent_logger.debug(message_or_progname_or_tags, progname_or_tags, &block)
    end
  end

  # Return +true+ if +DEBUG+ messages are being logged.
  #
  # @return [Boolean]
  def debug?
    level <= Logger::DEBUG
  end

  # Set the log level to debug.
  #
  # @return [void]
  def debug!
    self.level = Logger::DEBUG
  end

  # Log a message when the severity is not known. Unknown messages will always appear in the log.
  # The message can be passed in either the +message+ argument or in a block.
  #
  # @param [Object] message_or_progname_or_tags The message to log or progname
  #   if the message is passed in a block.
  # @param [String, Hash] progname_or_tags The name of the program that is logging the message or tags
  #   if the message is passed in a block.
  # @return [void]
  def unknown(message_or_progname_or_tags = nil, progname_or_tags = nil, &block)
    call_with_local_overrides do
      @parent_logger.unknown(message_or_progname_or_tags, progname_or_tags, &block)
    end
  end

  # Add a message when the severity is not known.
  #
  # @param [Object] msg The message to log.
  # @return [void]
  def <<(msg)
    call_with_local_overrides do
      @parent_logger << msg
    end
  end

  # ::Logger compatible method to add a log entry.
  #
  # @param [Integer, Symbol, String] severity The severity of the message.
  # @param [Object] message The message to log.
  # @param [String] progname The name of the program that is logging the message.
  # @return [void]
  def add(severity, message = nil, progname = nil, &block)
    if message.nil?
      if block
        message = block
      else
        message = progname
        progname = nil
      end
    end
    call_with_local_overrides do
      @parent_logger.add(severity, message, progname, &block)
    end
  end

  alias_method :log, :add

  # Proxy any missing methods to the parent logger
  #
  # @param [Symbol] method_name The name of the method being called
  # @param [Array] args The arguments passed to the method
  # @param [Proc] block The block passed to the method
  # @return [Object] The result of calling the method on the parent logger
  def method_missing(method_name, *args, **kwargs, &block)
    if @parent_logger.respond_to?(method_name)
      @parent_logger.public_send(method_name, *args, **kwargs, &block)
    else
      super
    end
  end

  # Check if this object responds to a method by checking both the local methods
  # and the parent logger's methods
  #
  # @param [Symbol] method_name The name of the method to check
  # @param [Boolean] include_private Whether to include private methods
  # @return [Boolean] True if the method is supported
  def respond_to_missing?(method_name, include_private = false)
    @parent_logger.respond_to?(method_name, include_private) || super
  end

  private

  def call_with_local_overrides
    @parent_logger.with_level(level) do
      @parent_logger.set_progname(@local_progname) do
        @parent_logger.tag(@local_tags) do
          yield
        end
      end
    end
  end
end
