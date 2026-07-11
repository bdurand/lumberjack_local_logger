# frozen_string_literal: true

# Helper module for setting up a local logger for a class.
#
# This module provides functionality to create a local logger that inherits from a parent logger
# but can have different settings such as level, progname, and attributes. It's useful for creating
# contextual logging within specific classes without affecting the global logger configuration.
#
# @example Basic usage
#   # Set up the default logger (typically in an initializer)
#   Lumberjack::LocalLogger.default_logger = Rails.logger
#
#   class UserService
#     include Lumberjack::LocalLogger
#
#     setup_logger do |logger|
#       logger.level = :info
#       logger.progname = "UserService"
#       logger.tag!(component: "user_management")
#     end
#
#     def create_user(email, name)
#       logger.info("Creating user", email: email)
#       # ... business logic ...
#     end
#   end
module Lumberjack::LocalLogger
  VERSION = File.read(File.join(__dir__, "..", "..", "VERSION")).strip.freeze

  # Sentinel value used in generated wrapper methods to distinguish omitted optional
  # arguments from explicitly passed values. This cannot be a private constant because
  # it is referenced by its fully qualified name in generated code.
  #
  # @api private
  UNSET = Object.new.freeze

  class << self
    # The default logger to use when no parent logger is specified.
    #
    # @return [Lumberjack::ContextLogger, nil] the default logger
    attr_accessor :default_logger

    # Called when the module is included in a class. Sets up the ClassMethods module.
    #
    # @param base [Class] The class that is including this module
    # @return [void]
    def included(base)
      base.extend(ClassMethods)
    end
  end

  module ClassMethods
    # Sets up the local logger for the class. This can be used to set default attributes, level, and progname.
    #
    # @param from [Lumberjack::ContextLogger, nil] Specify the parent logger to use. This is shorthand for
    #   calling `self.parent_logger = from`.
    # @param block [Proc, nil] A block that will be called with the local logger instance when it is created. You
    #   can use this block to set the local logger's attributes, level, and progname.
    # @return [void]
    #
    # @example Basic setup
    #   class MyClass
    #     include Lumberjack::LocalLogger
    #
    #     setup_logger do |logger|
    #       logger.level = :debug
    #       logger.progname = "MyClass"
    #       logger.tag!(component: "system_component")
    #     end
    #   end
    #
    # @example With specific parent logger
    #   class MyClass
    #     include Lumberjack::LocalLogger
    #
    #     setup_logger(from: custom_logger) do |logger|
    #       logger.level = :info
    #     end
    #   end
    def setup_logger(from: nil, &block)
      @__logger_setup_block = block
      @__local_logger_logger = nil
      self.parent_logger = from if from
    end

    # Wraps a method with logging functionality, allowing for local attributes to be set.
    # This can be useful to keep logging concerns separate from business logic to keep your code clean.
    #
    # The method must already be defined before calling this method.
    #
    # @param method_name [Symbol] The name of the instance method to wrap. The method must already
    #   have been defined before calling this method.
    # @param attributes [Hash] Attributes to set on the local logger. These attributes will be added to all log
    #   entries made by the local logger during the method call.
    # @param block [Proc, nil] An optional block to execute within the context of the wrapped method. The
    #   block will be called with the original method arguments. You can add additional logging related
    #   code in this block like setting log attributes based on the method arguments.
    # @return [void]
    # @raise [ArgumentError] If the method is not already defined
    #
    # @example Basic usage with static attributes
    #   class PaymentService
    #     include Lumberjack::LocalLogger
    #
    #     def process_payment(amount, currency)
    #       logger.info("Processing payment")
    #       # ... business logic ...
    #     end
    #
    #     add_log_attributes(:process_payment, service: "payment", version: "v2")
    #   end
    #
    # @example With dynamic attributes using a block
    #   class PaymentService
    #     include Lumberjack::LocalLogger
    #
    #     def process_payment(amount, currency)
    #       logger.info("Processing payment")
    #       # ... business logic ...
    #     end
    #
    #     add_log_attributes(:process_payment) do |amount, currency|
    #       logger.tag(amount: amount, currency: currency)
    #     end
    #   end
    def add_log_attributes(method_name, attributes = {}, &block)
      method_name = method_name.to_sym
      unless method_defined?(method_name) || private_method_defined?(method_name)
        raise ArgumentError, "Method #{method_name} is not defined"
      end

      visibility = if private_method_defined?(method_name)
        :private
      elsif protected_method_defined?(method_name)
        :protected
      else
        :public
      end

      static_local_attributes = Lumberjack::Utils.flatten_attributes(attributes)

      # Get the original method to inspect its signature
      original_method = instance_method(method_name)

      wrapper_module = Module.new

      # Stash the block and attributes in a private constant on the wrapper module. The
      # generated method references the constant lexically, so each wrapper always reads
      # its own data even when the same method is wrapped again in a subclass.
      wrapper_module.const_set(:LOCAL_LOG_DATA, [block, static_local_attributes].freeze)
      wrapper_module.send(:private_constant, :LOCAL_LOG_DATA)

      wrapper_code = build_add_log_attributes_wrapper_method(method_name, original_method.parameters)
      wrapper_module.module_eval(wrapper_code, __FILE__, __LINE__)
      wrapper_module.send(visibility, method_name) unless visibility == :public

      prepend wrapper_module
    end

    # Set the parent logger for this class. This logger will be used as the base logger for the local logger.
    # If this is not set, then the value in `Lumberjack::LocalLogger.default_logger` will be used.
    #
    # @param value [Lumberjack::ContextLogger, nil] The parent logger to set.
    # @return [void]
    def parent_logger=(value)
      @__local_logger_parent_logger = value
      @__local_logger_logger = nil
    end

    # Gets the parent logger for this class. If a parent logger is not set on this class, then
    # one will be looked up in the superclass chain. If no superclass has set a parent logger, then
    # the value in `Lumberjack::LocalLogger.default_logger` will be used.
    #
    # @return [Lumberjack::ContextLogger, nil] The parent logger for this class or nil if no parent logger is set.
    def parent_logger
      parent = @__local_logger_parent_logger if defined?(@__local_logger_parent_logger)
      parent ||= superclass.parent_logger if superclass.include?(Lumberjack::LocalLogger)
      parent || Lumberjack::LocalLogger.default_logger
    end

    # Get the local logger for the class. If no parent logger is defined, this will return nil.
    # The local logger is a fork of the parent logger with any configuration applied in the setup_logger block.
    #
    # The local logger is cached, but it will be rebuilt if the logger it was forked from changes
    # (i.e. the parent logger is changed on this class or a superclass, or the default logger changes).
    #
    # @return [Lumberjack::ContextLogger, nil] The local logger for the class or nil if not defined.
    def logger
      wrapped_logger = __local_logger_wrapped_logger
      return nil unless wrapped_logger

      cached_source, cached_logger = @__local_logger_logger if defined?(@__local_logger_logger)
      return cached_logger if cached_logger && cached_source.equal?(wrapped_logger)

      __local_logger_mutex.synchronize do
        cached_source, cached_logger = @__local_logger_logger if defined?(@__local_logger_logger)
        return cached_logger if cached_logger && cached_source.equal?(wrapped_logger)

        logger = wrapped_logger.fork
        if defined?(@__logger_setup_block) && @__logger_setup_block
          @__logger_setup_block.call(logger)
        end

        @__local_logger_logger = [wrapped_logger, logger]
        logger
      end
    end

    private

    # The logger that the local logger should be forked from. This is the superclass local logger
    # unless a parent logger has been explicitly set on this class.
    #
    # @return [Lumberjack::ContextLogger, nil]
    # @api private
    def __local_logger_wrapped_logger
      wrapped_logger = nil
      if superclass.include?(Lumberjack::LocalLogger) && !(defined?(@__local_logger_parent_logger) && @__local_logger_parent_logger)
        wrapped_logger = superclass.logger
      end
      wrapped_logger || parent_logger
    end

    # Mutex guarding construction of the memoized local logger for this class.
    #
    # @return [Mutex]
    # @api private
    def __local_logger_mutex
      @__local_logger_mutex ||= Mutex.new
    end

    # Builds the source code for the wrapper method defined by add_log_attributes.
    #
    # The wrapper preserves the wrapped method's signature. Optional positional and keyword
    # parameters default to the UNSET sentinel so that arguments the caller omitted can be
    # omitted from the call to super as well, allowing the wrapped method's own default
    # values to apply. The optional block passed to add_log_attributes is called with the
    # method arguments, with nil in place of any omitted optional arguments.
    #
    # @param method_name [Symbol] The name of the method being wrapped
    # @param parameters [Array<Array>] The parameters array from Method#parameters
    # @return [String] The Ruby source code for the wrapper method
    # @api private
    def build_add_log_attributes_wrapper_method(method_name, parameters)
      unset = "Lumberjack::LocalLogger::UNSET"
      signature_parts = []
      exec_args = []
      forward_lines = []
      block_name = nil
      positional = false
      keywords = false

      parameters.each_with_index do |(type, name), index|
        # Parameters can be anonymous (e.g. def foo(*), C methods, or def foo(...)) in which
        # case the reported name is nil or not a usable identifier. Substitute generated names.
        name = nil unless name&.match?(/\A[A-Za-z_]\w*\z/)

        case type
        when :req
          name ||= "__ll_arg#{index}"
          signature_parts << name
          exec_args << name
          forward_lines << "__ll_args << #{name}"
          positional = true
        when :opt
          name ||= "__ll_arg#{index}"
          signature_parts << "#{name} = #{unset}"
          exec_args << "(#{unset}.equal?(#{name}) ? nil : #{name})"
          forward_lines << "__ll_args << #{name} unless #{unset}.equal?(#{name})"
          positional = true
        when :rest
          name ||= "__ll_rest_args"
          signature_parts << "*#{name}"
          exec_args << "*#{name}"
          forward_lines << "__ll_args.concat(#{name})"
          positional = true
        when :keyreq
          signature_parts << "#{name}:"
          exec_args << "#{name}: #{name}"
          forward_lines << "__ll_kwargs[:#{name}] = #{name}"
          keywords = true
        when :key
          signature_parts << "#{name}: #{unset}"
          exec_args << "#{name}: (#{unset}.equal?(#{name}) ? nil : #{name})"
          forward_lines << "__ll_kwargs[:#{name}] = #{name} unless #{unset}.equal?(#{name})"
          keywords = true
        when :keyrest
          name ||= "__ll_kw_args"
          signature_parts << "**#{name}"
          exec_args << "**#{name}"
          forward_lines << "__ll_kwargs.update(#{name})"
          keywords = true
        when :block
          block_name = name
        end
      end

      # Always accept and forward a block so that wrapped methods that yield still work.
      block_name ||= "__ll_block"
      signature_parts << "&#{block_name}"

      setup_lines = []
      setup_lines << "__ll_args = []" if positional
      setup_lines << "__ll_kwargs = {}" if keywords

      super_args = []
      super_args << "*__ll_args" if positional
      super_args << "**__ll_kwargs" if keywords
      super_args << "&#{block_name}"

      exec_args << "&__ll_wrapper_block"

      <<~RUBY
        def #{method_name}(#{signature_parts.join(", ")})
          __ll_wrapper_block, __ll_local_attributes = LOCAL_LOG_DATA

          logger.tag(__ll_local_attributes) do
            instance_exec(#{exec_args.join(", ")}) if __ll_wrapper_block
            #{setup_lines.join("\n    ")}
            #{forward_lines.join("\n    ")}
            super(#{super_args.join(", ")})
          end
        end
      RUBY
    end
  end

  # Get the local logger for the instance. This returns the same logger as the class method.
  # If no parent logger is defined, this will return nil.
  #
  # @return [Lumberjack::ContextLogger, nil] The local logger for the class or nil if not defined.
  def logger
    self.class.logger
  end
end

require_relative "local_logger/railtie" if defined?(Rails::Railtie)
