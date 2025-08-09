# frozen_string_literal: true

# Helper module for setting up a local logger for a class.
#
# @example
#
# # The default logger needs to be setup in an intializer when the application starts.
# # In a Rails application you would call this from an initializer:
# Lumberjack::LocalLogger::Helper.default_logger = Rails.logger
#
module Lumberjack::LocalLogger::Helper
  class << self
    def included(base)
      base.extend(ClassMethods)
    end

    attr_accessor :default_logger
  end

  module ClassMethods
    # Wraps a method with logging functionality, allowing for local tags and global tags to be set.
    # This can be useful to keep logging concerns separate from business logic to keep your code clean.
    #
    # @params method_name [Symbol] The name of the instance method to wrap. The method must already
    #   have been defined before calling this method.
    # @params local_tags [Hash] Tags to set on the local logger. These tags will be added to all log
    #   entries made by the local logger during the method call.
    # @params global_tags [Hash] Tags to set on the parent logger. These tags will be added to all log
    #   entries made by the parent logger during the method call even those made outside of this class.
    # @params block [Proc] An optional block to execute within the context of the wrapped method. The
    #   block will be called with the original method arguments. You can add additional logging related
    #   code in this block like setting log tags based on the method arguments.
    # @return [void]
    def add_log_tags_to_method(method_name, local_tags: {}, global_tags: {}, &block)
      unless instance_methods.include?(method_name.to_sym)
        raise ArgumentError, "Method #{method_name} is not defined"
      end

      static_local_tags = Lumberjack::Utils.flatten_tags(local_tags)
      static_global_tags = Lumberjack::Utils.flatten_tags(global_tags)

      # Get the original method to inspect its signature
      original_method = instance_method(method_name)

      # Generate method signature components
      signature, call_args = build_add_log_tags_to_method_signature_and_call_args(original_method.parameters)

      wrapper_module = Module.new

      # Create a lambda that captures the closure variables
      data_accessor = lambda { [block, static_local_tags, static_global_tags] }

      # Define a private method in the wrapper module to access the closure variables
      wrapper_module.define_method(:"__get_wrapped_logger_data_for_#{method_name}", &data_accessor)
      wrapper_module.send(:private, :"__get_wrapped_logger_data_for_#{method_name}")

      wrapper_module.module_eval <<-RUBY, __FILE__, __LINE__ + 1
        def #{method_name}(#{signature})
          wrapper_block, local_tags, global_tags = __get_wrapped_logger_data_for_#{method_name}

          logger.tag(global_tags) do
            logger.tag_local(local_tags) do
              instance_exec(#{call_args}, &wrapper_block) if wrapper_block
              super
            end
          end
        end
      RUBY

      prepend wrapper_module
    end

    # Set the parent logger for this class. This logger will be used as the base logger for the local logger.
    # If this is not set, then the value in `Lumberjack::LocalLogger::Helper.default_logger` will be used.
    #
    # @param value [Lumberjack::Logger] The parent logger to set.
    # @return [void]
    def parent_logger=(value)
      @__local_logger_parent_logger = value
      @__local_logger_logger = nil
    end

    # Gets the parent logger for this class. If a parent logger is not set on this class, then
    # one will be looked up in the superclass chain. If no superclass has set a parent logger, then
    # the value in `Lumberjack::LocalLogger::Helper.default_logger` will be used.
    #
    # @return [Lumberjack::Logger, nil] The parent logger for this class or nil if no parent logger is set.
    def parent_logger
      parent = @__local_logger_parent_logger if defined?(@__local_logger_parent_logger)
      parent ||= superclass.parent_logger if superclass.include?(Lumberjack::LocalLogger::Helper)
      parent || Lumberjack::LocalLogger::Helper.default_logger
    end

    # Sets the program name for the local logger.
    #
    # @param value [String] The program name to set.
    # @return [void]
    def logger_progname=(value)
      @__local_logger_logger_progname = value&.dup&.freeze
      @__local_logger_logger = nil
    end

    # Gets the program name for the local logger.
    #
    # @return [String, nil] The program name for the local logger or nil if not set.
    def logger_progname
      value = @__local_logger_logger_progname if defined?(@__local_logger_logger_progname)
      value ||= superclass.logger_progname if superclass.include?(Lumberjack::LocalLogger::Helper)
      value
    end

    # Set logging tags on the local logger.
    #
    #
    # @param value [Hash] The logging tags to set.
    # @return [void]
    def logger_tags=(value)
      @__local_logger_logger_tags = value.nil? ? nil : Lumberjack::Utils.flatten_tags(value).freeze
      @__local_logger_logger = nil
    end

    # Get the tags for the local logger. This will include any tags set in the superclass.
    #
    # @return [Hash] The tags for the local logger.
    def logger_tags
      tags = superclass.logger_tags&.dup if superclass.include?(Lumberjack::LocalLogger::Helper)
      tags ||= {}
      tags = tags.merge(@__local_logger_logger_tags) if defined?(@__local_logger_logger_tags) && !@__local_logger_logger_tags.nil?
      tags
    end

    # Set the logging level for the local logger. A value of nil will defer the level to that of the
    # parent logger.
    #
    # @param value [Integer, String, Symbol, Lumberjack::Severity, nil] The logging level to set.
    def logger_level=(value)
      @__local_logger_logger_level = value.nil? ? nil : Lumberjack::Severity.coerce(value)
      @__local_logger_logger = nil
    end

    # Get the logging level for the local logger.
    #
    # @return [Integer, nil] The logging level for the local logger.
    def logger_level
      value = @__local_logger_logger_level if defined?(@__local_logger_logger_level)
      value ||= superclass.logger_level if superclass.include?(Lumberjack::LocalLogger::Helper)
      value
    end

    # Get the local logger for the class. If no parent logger is defined, this will return nil.
    #
    # @return [Lumberjack::LocalLogger, nil] The local logger for the class or nil if not defined.
    def logger
      return @__local_logger_logger if defined?(@__local_logger_logger) && @__local_logger_logger

      wrapped_logger = parent_logger
      return nil unless wrapped_logger

      logger = Lumberjack::LocalLogger.new(wrapped_logger, level: logger_level, progname: logger_progname, tags: logger_tags)
      @__local_logger_logger = logger
      logger
    end

    private

    # Builds the method signature and call args based on the method parameters
    #
    # @param parameters [Array] The parameters array from Method#parameters
    # @return [Array<String>] An array containing [signature, call_args]
    def build_add_log_tags_to_method_signature_and_call_args(parameters)
      signature_parts = []
      call_parts = []

      parameters.each do |type, name|
        case type
        when :req
          signature_parts << name.to_s
          call_parts << name.to_s
        when :opt
          signature_parts << "#{name} = nil"
          call_parts << name.to_s
        when :rest
          signature_parts << "*#{name}"
          call_parts << "*#{name}"
        when :keyreq
          signature_parts << "#{name}:"
          call_parts << "#{name}: #{name}"
        when :key
          signature_parts << "#{name}: nil"
          call_parts << "#{name}: #{name}"
        when :keyrest
          signature_parts << "**#{name}"
          call_parts << "**#{name}"
        when :block
          signature_parts << "&#{name}"
          call_parts << "&#{name}"
        end
      end

      [signature_parts.join(", "), call_parts.join(", ")]
    end
  end

  # Get the local logger for the class. If no parent logger is defined, this will return nil.
  #
  # @return [Lumberjack::LocalLogger, nil] The local logger for the class or nil if not defined.
  def logger
    self.class.logger
  end
end
