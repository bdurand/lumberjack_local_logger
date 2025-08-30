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
  class << self
    # @!attribute [rw] default_logger
    #   @return [Lumberjack::ContextLogger, nil] The default logger to use when no parent logger is specified
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
    #   calling `self.parent_logger = parent_logger`.
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
    def setup_logger(from = nil, &block)
      @__logger_setup_block = block
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
      unless instance_methods.include?(method_name.to_sym)
        raise ArgumentError, "Method #{method_name} is not defined"
      end

      static_local_attributes = Lumberjack::Utils.flatten_attributes(attributes)

      # Get the original method to inspect its signature
      original_method = instance_method(method_name)

      # Generate method signature components
      signature, call_args = build_add_log_attributes_to_method_signature_and_call_args(original_method.parameters)

      wrapper_module = Module.new

      # Create a lambda that captures the closure variables
      data_accessor = lambda { [block, static_local_attributes] }

      # Define a private method in the wrapper module to access the closure variables
      wrapper_module.define_method(:"__get_wrapped_logger_data_for_#{method_name}", &data_accessor)
      wrapper_module.send(:private, :"__get_wrapped_logger_data_for_#{method_name}")

      wrapper_module.module_eval <<-RUBY, __FILE__, __LINE__ + 1
        def #{method_name}(#{signature})
          wrapper_block, local_attributes = __get_wrapped_logger_data_for_#{method_name}

          logger.tag(local_attributes) do
            instance_exec(#{call_args}, &wrapper_block) if wrapper_block
            super
          end
        end
      RUBY

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
    # @return [Lumberjack::ContextLogger, nil] The local logger for the class or nil if not defined.
    def logger
      return @__local_logger_logger if defined?(@__local_logger_logger) && @__local_logger_logger

      wrapped_logger = nil
      if superclass.include?(Lumberjack::LocalLogger) && !(defined?(@__local_logger_parent_logger) && @__local_logger_parent_logger)
        wrapped_logger = superclass.logger
      end
      wrapped_logger ||= parent_logger

      return nil unless wrapped_logger

      logger = wrapped_logger.fork
      if defined?(@__logger_setup_block) && @__logger_setup_block
        @__logger_setup_block.call(logger)
      end

      @__local_logger_logger = logger
      logger
    end

    private

    # Builds the method signature and call args based on the method parameters.
    # This is used internally by add_log_attributes to generate the wrapper method.
    #
    # @param parameters [Array<Array>] The parameters array from Method#parameters
    # @return [Array<String>] An array containing [signature, call_args]
    # @api private
    def build_add_log_attributes_to_method_signature_and_call_args(parameters)
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

  # Get the local logger for the instance. This returns the same logger as the class method.
  # If no parent logger is defined, this will return nil.
  #
  # @return [Lumberjack::ContextLogger, nil] The local logger for the class or nil if not defined.
  def logger
    self.class.logger
  end
end
