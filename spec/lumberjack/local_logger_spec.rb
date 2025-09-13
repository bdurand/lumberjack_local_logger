# frozen_string_literal: true

require "spec_helper"

class MyClass
  include Lumberjack::LocalLogger

  setup_logger do |logger|
    logger.tag!(component: -> { name })
    logger.level = :info
    logger.progname = "my_class"
  end

  attr_reader :action

  def initialize(action)
    @action = action
  end

  def perform(value, option: nil)
    logger.info("Performing action")
    UpCaser.new(value).call
  end

  add_log_attributes(:perform, method: "perform") do |value, option:|
    logger.tag(value: value, option: option, action: action)
  end

  def debug_perform(value, option: nil)
    logger.debug("Performing debug action with #{value.inspect}")
    result = perform(value, option: option)
    logger.debug("Debug action completed with result: #{result.inspect}")
  end

  add_log_attributes(:debug_perform, debugging: "local") do
    logger.level = :debug
  end

  def execute(value)
    logger.info("Calling execute")
    UpCaser.new(value).call
  end

  add_log_attributes(:execute) do
    logger.tag(execute: action, big_action: @action.to_s.upcase)
  end

  def shadow_perform(value, option: nil)
    UpCaser.new(value).call
  end
end

class MySubclass < MyClass
  setup_logger do |logger|
    logger.tag!(subcomponent: "MySubclass")
    logger.level = :debug
    logger.progname = "MySubclassProgram"
  end
end

class InheritingSubclass < MyClass
end

class UpCaser
  def initialize(value)
    @value = value
  end

  def call
    MyClass.logger.parent_logger.info("Calling upcase")
    @value.to_s.upcase
  end
end

RSpec.describe Lumberjack::LocalLogger do
  let(:parent_logger) { Lumberjack::Logger.new(:test, level: :warn) }
  let(:last_entry) { parent_logger.device.entries.last }

  around do |example|
    MyClass.parent_logger = parent_logger
    example.run
  ensure
    Lumberjack::LocalLogger.default_logger = nil
    MyClass.parent_logger = nil
    MySubclass.parent_logger = nil
    InheritingSubclass.parent_logger = nil
  end

  describe "VERSION" do
    it "has a version number" do
      expect(Lumberjack::LocalLogger::VERSION).not_to be nil
    end
  end

  describe ".parent_logger" do
    it "returns the parent logger" do
      expect(MyClass.parent_logger).to equal(parent_logger)
    end

    it "inherits the superclass parent logger" do
      expect(InheritingSubclass.parent_logger).to equal(parent_logger)
    end

    it "can set a different parent logger per subclass" do
      other_logger = Lumberjack::Logger.new(:test, level: :error)
      MySubclass.parent_logger = other_logger
      expect(MySubclass.parent_logger).to equal(other_logger)
      expect(MyClass.parent_logger).to equal(parent_logger)
    end

    it "uses the default logger if no parent logger is set" do
      MyClass.parent_logger = nil
      expect(MyClass.parent_logger).to be_nil

      Lumberjack::LocalLogger.default_logger = parent_logger
      expect(MyClass.parent_logger).to equal(parent_logger)
    end
  end

  describe ".logger" do
    it "returns a local logger with meta data set up" do
      logger = MyClass.logger
      expect(logger).to be_a(Lumberjack::ContextLogger)
      expect(logger.progname).to eq("my_class")
      expect(logger.level).to eq(Logger::INFO)
      expect(logger.attributes["component"]).to be_a(Proc)
    end

    it "returns a different logger instance for each class" do
      expect(InheritingSubclass.logger).to be_a(Lumberjack::ContextLogger)
      expect(MyClass.logger).not_to equal(InheritingSubclass.logger)
    end

    it "returns nil if no parent logger is set" do
      MyClass.parent_logger = nil
      expect(MyClass.logger).to be_nil
    end
  end

  describe "#logger" do
    it "returns the class logger" do
      expect(MyClass.new("foobar").logger).to equal(MyClass.logger)
    end
  end

  describe ".setup_logger" do
    it "sets up the local logger with the block" do
      expect(MyClass.logger.progname).to eq("my_class")
      expect(MyClass.logger.parent_logger.progname).to be_nil
    end

    it "inherits the superclass logger attributes" do
      InheritingSubclass.logger.info("test")
      expect(last_entry.attributes).to eq({"component" => "MyClass"})
    end

    it "can merges the superclass logger attributes" do
      MySubclass.logger.info("test")
      expect(last_entry.attributes).to eq({"component" => "MyClass", "subcomponent" => "MySubclass"})
      expect(MySubclass.logger.level).to eq(Logger::DEBUG)
      expect(MySubclass.logger.progname).to eq("MySubclassProgram")
    end

    it "calls procs for dynamic attributes at runtime from the class binding" do
      logger = MySubclass.logger
      logger.info("test")
      expect(last_entry.attributes).to eq({"component" => "MyClass", "subcomponent" => "MySubclass"})
    end
  end

  describe "#add_log_attributes" do
    before do
      parent_logger.level = :info
    end

    it "does not change the method signature" do
      expect(MyClass.instance_method(:perform).arity).to eq(MyClass.instance_method(:shadow_perform).arity)
    end

    it "returns the expected value" do
      expect(MyClass.new("foobar").perform("foobar")).to eq("FOOBAR")
    end

    it "wraps a method with logging meta data" do
      logs = capture_logger(parent_logger) { MyClass.new("foobar").perform("arg1", option: "arg2") }
      expect(logs).to(
        include_log_entry(
          message: "Performing action",
          attributes: {
            component: "MyClass",
            action: "foobar",
            method: "perform",
            value: "arg1",
            option: "arg2"
          }
        )
      )

      expect(logs).to include_log_entry(message: "Calling upcase", attributes: {component: nil})
      expect(logs).to_not include_log_entry(message: "Calling upcase", attributes: {method: "perform"})
    end

    it "handles calling the logging setup block without optional values" do
      logs = capture_logger(parent_logger) { MyClass.new("foobar").perform("arg1") }
      expect(logs).to include_log_entry(message: "Performing action", attributes: {component: "MyClass", action: "foobar", method: "perform", value: "arg1"})
    end

    it "adds attributes without the optional block" do
      logs = capture_logger(parent_logger) { MyClass.new("foobar").debug_perform("arg1", option: "arg2") }
      expect(logs).to include_log_entry(message: "Performing action", attributes: {debugging: "local"})
    end

    it "merges adds attributes from wrapped method calling each other" do
      logs = capture_logger(parent_logger) { MyClass.new("foobar").debug_perform("arg1", option: "arg2") }
      expect(logs).to(
        include_log_entry(
          message: "Performing action",
          attributes: {
            component: "MyClass",
            action: "foobar",
            method: "perform",
            value: "arg1",
            option: "arg2",
            debugging: "local"
          }
        )
      )
    end

    it "handles a block defined without the method arguments" do
      logs = capture_logger(parent_logger) { MyClass.new("foobar").execute("arg1") }
      expect(logs).to include_log_entry(message: "Calling execute", attributes: {execute: "foobar"})
    end

    it "can access instance variables in the block" do
      logs = capture_logger(parent_logger) { MyClass.new("foobar").execute("arg1") }
      expect(logs).to include_log_entry(message: "Calling execute", attributes: {big_action: "FOOBAR"})
    end
  end
end
