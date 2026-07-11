# frozen_string_literal: true

require "spec_helper"

class MyClass
  include Lumberjack::LocalLogger

  setup_logger do |logger|
    logger.tag!(component: -> { name }, aspect: "base_class")
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
    logger.tag!(subcomponent: "MySubclass", aspect: "subclass")
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

class ArgumentEdgeCases
  include Lumberjack::LocalLogger

  def greet(name = "world", punct: "!")
    "hello #{name}#{punct}"
  end

  add_log_attributes(:greet, method: "greet")

  def ping
    "pong"
  end

  add_log_attributes(:ping, method: "ping")

  def with_block(value, &block)
    block.call(value)
  end

  add_log_attributes(:with_block, method: "with_block")

  def yielder
    yield 21
  end

  add_log_attributes(:yielder, method: "yielder")

  def anon_args(*)
    "anon"
  end

  add_log_attributes(:anon_args, method: "anon_args")

  def everything(a, b = 5, *rest, k:, j: 7, **options, &block)
    [a, b, rest, k, j, options, block&.call]
  end

  add_log_attributes(:everything) do |a, b, *rest, k:, j:, **options|
    logger.tag(a: a, b: b, j: j)
  end

  private

  def hidden
    "hidden"
  end

  add_log_attributes(:hidden, method: "hidden")

  protected

  def shielded
    "shielded"
  end

  add_log_attributes(:shielded, method: "shielded")
end

RSpec.describe Lumberjack::LocalLogger do
  let(:parent_logger) { Lumberjack::Logger.new(:test, level: :warn) }
  let(:last_entry) { parent_logger.device.entries.last }

  around do |example|
    MyClass.parent_logger = parent_logger
    ArgumentEdgeCases.parent_logger = parent_logger
    example.run
  ensure
    Lumberjack::LocalLogger.default_logger = nil
    MyClass.parent_logger = nil
    MySubclass.parent_logger = nil
    InheritingSubclass.parent_logger = nil
    ArgumentEdgeCases.parent_logger = nil
  end

  describe "VERSION" do
    it "has a version number" do
      expect(Lumberjack::LocalLogger::VERSION).not_to be nil
    end
  end

  describe "requiring the gem" do
    it "can be required without lumberjack being loaded first" do
      lib_dir = File.expand_path(File.join(__dir__, "..", "..", "lib"))
      success = system(RbConfig.ruby, "-I", lib_dir, "-e", "require 'lumberjack_local_logger'")
      expect(success).to be true
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

    it "returns the same logger instance while the parent logger is unchanged" do
      expect(MyClass.logger).to equal(MyClass.logger)
    end

    it "rebuilds a subclass logger when the superclass parent logger changes" do
      original_logger = InheritingSubclass.logger
      new_parent = Lumberjack::Logger.new(:test, level: :info)

      MyClass.parent_logger = new_parent

      expect(InheritingSubclass.logger).not_to equal(original_logger)
      InheritingSubclass.logger.info("rerouted")
      expect(new_parent.device.entries.last.message).to eq("rerouted")
    end

    it "rebuilds the logger when the default logger changes" do
      MyClass.parent_logger = nil
      Lumberjack::LocalLogger.default_logger = parent_logger
      original_logger = MyClass.logger

      new_default = Lumberjack::Logger.new(:test, level: :info)
      Lumberjack::LocalLogger.default_logger = new_default

      expect(MyClass.logger).not_to equal(original_logger)
      MyClass.logger.info("rerouted")
      expect(new_default.device.entries.last.message).to eq("rerouted")
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
      expect(last_entry.attributes).to eq({"component" => "MyClass", "aspect" => "base_class"})
    end

    it "can merges the superclass logger attributes" do
      MySubclass.logger.info("test")
      expect(last_entry.attributes).to eq({"component" => "MyClass", "subcomponent" => "MySubclass", "aspect" => "subclass"})
      expect(MySubclass.logger.level).to eq(Logger::DEBUG)
      expect(MySubclass.logger.progname).to eq("MySubclassProgram")
    end

    it "calls procs for dynamic attributes at runtime from the class binding" do
      logger = MySubclass.logger
      logger.info("test")
      expect(last_entry.attributes).to eq({"component" => "MyClass", "subcomponent" => "MySubclass", "aspect" => "subclass"})
    end

    it "sets the parent logger with the from option" do
      other_logger = Lumberjack::Logger.new(:test, level: :info)
      klass = Class.new do
        include Lumberjack::LocalLogger
      end
      klass.setup_logger(from: other_logger) do |logger|
        logger.progname = "from_option"
      end

      expect(klass.parent_logger).to equal(other_logger)
      expect(klass.logger.progname).to eq("from_option")
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

    it "preserves default values of optional arguments" do
      instance = ArgumentEdgeCases.new
      expect(instance.greet).to eq("hello world!")
      expect(instance.greet("ruby")).to eq("hello ruby!")
      expect(instance.greet("ruby", punct: "?")).to eq("hello ruby?")
    end

    it "preserves default values in methods with mixed argument types" do
      instance = ArgumentEdgeCases.new
      expect(instance.everything(1, k: "x") { "block!" }).to eq([1, 5, [], "x", 7, {}, "block!"])
      expect(instance.everything(1, 2, 3, k: "x", j: "y", extra: true)).to eq([1, 2, [3], "x", "y", {extra: true}, nil])
    end

    it "wraps methods with no arguments" do
      expect(ArgumentEdgeCases.new.ping).to eq("pong")
    end

    it "wraps methods with an explicit block argument" do
      expect(ArgumentEdgeCases.new.with_block(2) { |value| value * 3 }).to eq(6)
    end

    it "forwards implicit blocks to methods that yield" do
      expect(ArgumentEdgeCases.new.yielder { |value| value * 2 }).to eq(42)
    end

    it "wraps methods with anonymous arguments" do
      expect(ArgumentEdgeCases.new.anon_args(1, 2)).to eq("anon")
    end

    it "wraps private methods and keeps them private" do
      expect(ArgumentEdgeCases.private_method_defined?(:hidden)).to be true
      expect(ArgumentEdgeCases.public_method_defined?(:hidden)).to be false
      expect(ArgumentEdgeCases.new.send(:hidden)).to eq("hidden")
    end

    it "wraps protected methods and keeps them protected" do
      expect(ArgumentEdgeCases.protected_method_defined?(:shielded)).to be true
      expect(ArgumentEdgeCases.new.send(:shielded)).to eq("shielded")
    end

    it "raises an error if the method is not defined" do
      expect {
        ArgumentEdgeCases.add_log_attributes(:not_a_method)
      }.to raise_error(ArgumentError, "Method not_a_method is not defined")
    end

    it "merges attributes when a subclass wraps the same method again" do
      base_class = Class.new do
        include Lumberjack::LocalLogger

        def work
          logger.info("working")
          "done"
        end

        add_log_attributes(:work, base_attr: "from_base")
      end
      subclass = Class.new(base_class) do
        add_log_attributes(:work, sub_attr: "from_sub")
      end
      base_class.parent_logger = parent_logger

      logs = capture_logger(parent_logger) { subclass.new.work }

      expect(logs).to include_log_entry(message: "working", attributes: {base_attr: "from_base", sub_attr: "from_sub"})
    end
  end
end
