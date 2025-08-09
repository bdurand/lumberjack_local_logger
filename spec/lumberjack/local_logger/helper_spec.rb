# frozen_string_literal: true

require_relative "../../spec_helper"

class MyClass
  include Lumberjack::LocalLogger::Helper

  self.logger_tags = {component: "MyClass"}
  self.logger_level = :info
  self.logger_progname = "MyClass"

  attr_reader :action

  def initialize(action)
    @action = action
  end

  def perform(value, option: nil)
    logger.info("Performing action")
    UpCaser.new(value).call
  end

  add_log_tags_to_method(:perform, local_tags: {method: "perform"}) do |value, option:|
    logger.tag(value: value)
    logger.tag_local(option: option, action: action)
  end

  def debug_perform(value, option: nil)
    logger.debug("Performing debug action with #{value.inspect}")
    result = perform(value, option: option)
    logger.debug("Debug action completed with result: #{result.inspect}")
  end

  add_log_tags_to_method(:debug_perform, local_tags: {debugging: "local"}, global_tags: {debug: true})

  def execute(value)
    logger.info("Calling execute")
    UpCaser.new(value).call
  end

  add_log_tags_to_method(:execute) do
    logger.tag_local(execute: action, big_action: @action.to_s.upcase)
  end

  def shadow_perform(value, option: nil)
    UpCaser.new(value).call
  end
end

class MySubclass < MyClass
  self.logger_tags = {subcomponent: "MySubclass"}
  self.logger_level = :debug
  self.logger_progname = "MySubclassProgram"
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

describe Lumberjack::LocalLogger::Helper do
  let(:output) { StringIO.new }
  let(:parent_logger) { Lumberjack::Logger.new(output, level: :warn) }
  let(:logs) { output.string }

  around do |example|
    MyClass.parent_logger = parent_logger
    example.run
  ensure
    Lumberjack::LocalLogger::Helper.default_logger = nil
    MyClass.parent_logger = nil
    MySubclass.parent_logger = nil
    InheritingSubclass.parent_logger = nil
  end

  describe ".parent_logger" do
    it "returns the parent logger" do
      expect(MyClass.parent_logger).to equal(parent_logger)
    end

    it "inherits the superclass parent logger" do
      expect(InheritingSubclass.parent_logger).to equal(parent_logger)
    end

    it "can set a different parent logger per subclass" do
      other_logger = Lumberjack::Logger.new(output, level: :error)
      MySubclass.parent_logger = other_logger
      expect(MySubclass.parent_logger).to equal(other_logger)
      expect(MyClass.parent_logger).to equal(parent_logger)
    end

    it "uses the default logger if no parent logger is set" do
      MyClass.parent_logger = nil
      expect(MyClass.parent_logger).to be_nil

      Lumberjack::LocalLogger::Helper.default_logger = parent_logger
      expect(MyClass.parent_logger).to equal(parent_logger)
    end
  end

  describe ".logger" do
    it "returns a local logger with meta data set up" do
      logger = MyClass.logger
      expect(logger).to be_a(Lumberjack::LocalLogger)
      expect(logger.progname).to eq("MyClass")
      expect(logger.level).to eq(Logger::INFO)
      expect(logger.local_tags).to eq({"component" => "MyClass"})
    end

    it "returns a different logger instance for each class" do
      expect(InheritingSubclass.logger).to be_a(Lumberjack::LocalLogger)
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

  describe "#logger_level" do
    it "sets the local logger level" do
      expect(MyClass.logger_level).to eq(Logger::INFO)
      expect(MyClass.logger.level).to eq(Logger::INFO)
      expect(MyClass.logger.parent_logger.level).to eq(Logger::WARN)
    end

    it "inherits the superclass logger level" do
      expect(InheritingSubclass.logger_level).to eq(Logger::INFO)
      expect(InheritingSubclass.logger.level).to eq(Logger::INFO)
      expect(InheritingSubclass.logger.parent_logger.level).to eq(Logger::WARN)
    end

    it "can override the superclass logger level" do
      expect(MySubclass.logger_level).to eq(Logger::DEBUG)
      expect(MySubclass.logger.level).to eq(Logger::DEBUG)
      expect(MySubclass.logger.parent_logger.level).to eq(Logger::WARN)
    end
  end

  describe "#progname" do
    it "sets the local logger progname" do
      expect(MyClass.logger_progname).to eq("MyClass")
      expect(MyClass.logger.progname).to eq("MyClass")
      expect(InheritingSubclass.logger.parent_logger.progname).to be_nil
    end

    it "inherits the superclass logger progname" do
      expect(InheritingSubclass.logger_progname).to eq("MyClass")
      expect(InheritingSubclass.logger.progname).to eq("MyClass")
      expect(InheritingSubclass.logger.parent_logger.progname).to be_nil
    end

    it "can override the superclass logger progname" do
      expect(MySubclass.logger_progname).to eq("MySubclassProgram")
      expect(MySubclass.logger.progname).to eq("MySubclassProgram")
      expect(InheritingSubclass.logger.parent_logger.progname).to be_nil
    end
  end

  describe "#logger_tags" do
    it "sets the local logger tags" do
      expect(MyClass.logger_tags).to eq({"component" => "MyClass"})
      expect(MyClass.logger.local_tags).to eq({"component" => "MyClass"})
      expect(MyClass.logger.parent_logger.tags).to be_empty
    end

    it "inherits the superclass logger tags" do
      expect(InheritingSubclass.logger_tags).to eq({"component" => "MyClass"})
      expect(InheritingSubclass.logger.local_tags).to eq({"component" => "MyClass"})
      expect(MyClass.logger.parent_logger.tags).to be_empty
    end

    it "can merges the superclass logger tags" do
      expect(MySubclass.logger_tags).to eq({"component" => "MyClass", "subcomponent" => "MySubclass"})
      expect(MySubclass.logger.local_tags).to eq({"component" => "MyClass", "subcomponent" => "MySubclass"})
      expect(MyClass.logger.parent_logger.tags).to be_empty
    end
  end

  describe "#add_log_tags_to_method" do
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
          tags: {
            component: "MyClass",
            action: "foobar",
            method: "perform",
            value: "arg1",
            option: "arg2"
          }
        )
      )

      expect(logs).to include_log_entry(message: "Calling upcase", tags: {value: "arg1"})
      expect(logs).to_not include_log_entry(message: "Calling upcase", tags: {method: "perform"})
    end

    it "handles calling the logging setup block without optional values" do
      logs = capture_logger(parent_logger) { MyClass.new("foobar").perform("arg1") }
      expect(logs).to include_log_entry(message: "Performing action", tags: {component: "MyClass", action: "foobar", method: "perform", value: "arg1"})
    end

    it "adds tags without the optional block" do
      logs = capture_logger(parent_logger) { MyClass.new("foobar").debug_perform("arg1", option: "arg2") }
      expect(logs).to include_log_entry(message: "Performing action", tags: {debug: true, debugging: "local"})
    end

    it "merges adds tags from wrapped method calling each other" do
      logs = capture_logger(parent_logger) { MyClass.new("foobar").debug_perform("arg1", option: "arg2") }
      expect(logs).to(
        include_log_entry(
          message: "Performing action",
          tags: {
            component: "MyClass",
            action: "foobar",
            method: "perform",
            value: "arg1",
            option: "arg2",
            debug: true,
            debugging: "local"
          }
        )
      )
    end

    it "handles a block defined without the method arguments" do
      logs = capture_logger(parent_logger) { MyClass.new("foobar").execute("arg1") }
      expect(logs).to include_log_entry(message: "Calling execute", tags: {execute: "foobar"})
    end

    it "can access instance variables in the block" do
      logs = capture_logger(parent_logger) { MyClass.new("foobar").execute("arg1") }
      expect(logs).to include_log_entry(message: "Calling execute", tags: {big_action: "FOOBAR"})
    end
  end
end
