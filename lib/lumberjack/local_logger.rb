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

  # @param parent_logger [Lumberjack::Logger] The parent logger to proxy calls to.
  # @param level [nil, Symbol, String, Integer] Optional logging level for this logger. This will take precedence
  #   over the parent logger level.
  # @param progname [nil, String] Optional program name to use for log messages.
  # @param tags [nil, Hash] Optional tags to associate with log messages. These will be merged with the parent logger's tags
  #   for messages logged with this logger.
  def initialize(parent_logger, level: nil, progname: nil, tags: nil)
    @parent_logger = parent_logger
    @local_level = Lumberjack::Severity.coerce(level) unless level.nil?
    self.progname = progname
    @local_tags = Lumberjack::Utils.flatten_tags(tags).freeze unless tags.nil?
  end

  # Get the current log level.
  #
  # @return [Integer]
  def level
    Thread.current[:lumberjack_local_logger_level] || @local_level || @parent_logger.level
  end

  # Set the log level.
  #
  # @param severity [nil, Symbol, String, Integer] The new log level. Setting to nil will use the parent
  #   loggers level.
  # @return [void]
  def level=(severity)
    @local_level = if severity.nil?
      nil
    else
      Lumberjack::Severity.coerce(severity)
    end
  end

  # Temporarily set the log level for the duration of the block.
  #
  # @param temporary_level [Symbol, String, Integer] The temporary log level to use.
  # @return [Object] The result of the block.
  def with_level(temporary_level, &block)
    save_level = Thread.current[:lumberjack_local_logger_level]
    begin
      Thread.current[:lumberjack_local_logger_level] = temporary_level
      @parent_logger.with_level(temporary_level, &block)
    ensure
      Thread.current[:lumberjack_local_logger_level] = save_level
    end
  end

  # Rails compatibility.
  alias_method :log_at, :with_level

  # Temporarily set the log level for the duration of the block, but only for this logger
  # and not for the parent logger.
  #
  # @return [Object] The result of the block.
  def with_local_level(temporary_level, &block)
    save_level = Thread.current[:lumberjack_local_logger_level]
    begin
      Thread.current[:lumberjack_local_logger_level] = temporary_level
      yield
    ensure
      Thread.current[:lumberjack_local_logger_level] = save_level
    end
  end

  # Silence logging temporarily. Only errors will be logged by default.
  #
  # @param temporary_level [Symbol, String, Integer] The temporary log level to use. Defaults to Logger::ERROR.
  # @return [Object] The result of the block.
  def silence(temporary_level = Logger::ERROR, &block)
    with_level(temporary_level, &block)
  end

  # Set the program name for the local logger.
  #
  # @param value [String] The program name to set.
  # @return [void]
  def progname=(value)
    @local_progname = value&.dup&.freeze
  end

  # Get the program name for the logger.
  #
  # @return [String]
  def progname
    @local_progname || @parent_logger.progname
  end

  # Add local tags to all messages in a block. These tags will only apply to the messages logged
  # by this logger and will not propagate to the parent logger.
  #
  # @param tags [Hash] The tags to add.
  # @return [Object] The result of the block.
  def tag_local(tags = {}, &block)
    save_tags = Thread.current[:lumberjack_local_logger_tags]
    begin
      Thread.current[:lumberjack_local_logger_tags] = Lumberjack::Utils.flatten_tags(tags)
      yield
    ensure
      Thread.current[:lumberjack_local_logger_tags] = save_tags
    end
  end

  # Add local tags to all messages logged by this logger.
  #
  # @param tags [Hash] The tags to add.
  # @return [void]
  def add_local_tags(tags)
    tag_context = Lumberjack::TagContext.new(@local_tags&.dup || {})
    tag_context.tag(tags)
    @local_tags = tag_context.to_h.freeze
  end

  # Remove local tags from all messages logged by this logger.
  #
  # @param names [Array<String>, Array<Symbol>] The names of the tags to remove.
  # @return [void]
  def remove_local_tags(*names)
    return if @local_tags.nil?

    tag_context = Lumberjack::TagContext.new(@local_tags&.dup || {})
    tag_context.delete(*names)
    @local_tags = tag_context.to_h.freeze
  end

  # Get the local tags for the logger.
  #
  # @return [Hash<String, Object] The local tags for the logger.
  def local_tags
    tags = Thread.current[:lumberjack_local_logger_tags] || @local_tags || {}
    Lumberjack::TagContext.new(tags).to_h.freeze
  end

  # Get the tags for the logger including tags inherited from the parent logger.
  #
  # @return [Hash<String, Object>] The tags for the logger.
  def tags
    @parent_logger.tag(@local_tags) { @parent_logger.tags }
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
