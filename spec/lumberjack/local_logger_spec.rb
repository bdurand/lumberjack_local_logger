# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe Lumberjack::LocalLogger do
  let(:out) { StringIO.new }
  let(:parent_logger) { Lumberjack::Logger.new(out, level: :info) }

  describe "level" do
    let(:logger) { Lumberjack::LocalLogger.new(parent_logger, level: :debug) }

    it "can override the parent logger's level" do
      expect(logger.level).to eq(Logger::DEBUG)
      expect(logger.parent_logger.level).to eq(Logger::INFO)
    end

    it "can change the level" do
      logger.level = Logger::ERROR
      expect(logger.level).to eq(Logger::ERROR)
      expect(logger.parent_logger.level).to eq(Logger::INFO)
    end

    it "can change the level in a block" do
      logger.with_level(Logger::WARN) do
        expect(logger.level).to eq(Logger::WARN)
        expect(logger.parent_logger.level).to eq(Logger::WARN)
      end
      expect(logger.level).to eq(Logger::DEBUG)
      expect(logger.parent_logger.level).to eq(Logger::INFO)
    end

    it "can silence the logger" do
      logger.silence do
        expect(logger.level).to eq(Logger::ERROR)
      end
      expect(logger.level).to eq(Logger::DEBUG)
    end

    it "can silence the logger with log_at" do
      logger.log_at(Logger::ERROR) do
        expect(logger.level).to eq(Logger::ERROR)
      end
    end

    it "can determine if the log level is fatal" do
      expect(logger.fatal?).to be(true)
      logger.level = :unknown
      expect(logger.fatal?).to be(false)
    end

    it "can determine if the log level is error" do
      expect(logger.error?).to be(true)
      logger.level = :fatal
      expect(logger.error?).to be(false)
    end

    it "can determine if the log level is warn" do
      expect(logger.warn?).to be(true)
      logger.level = :error
      expect(logger.warn?).to be(false)
    end

    it "can determine if the log level is info" do
      expect(logger.info?).to be(true)
      logger.level = :warn
      expect(logger.info?).to be(false)
    end

    it "can determine if the log level is debug" do
      expect(logger.debug?).to be(true)
      logger.level = :info
      expect(logger.debug?).to be(false)
    end

    it "can set the log level to fatal" do
      logger.fatal!
      expect(logger.level).to eq(Logger::FATAL)
      expect(logger.parent_logger.level).to eq(Logger::INFO)
    end

    it "can set the log level to error" do
      logger.error!
      expect(logger.level).to eq(Logger::ERROR)
      expect(logger.parent_logger.level).to eq(Logger::INFO)
    end

    it "can set the log level to warn" do
      logger.warn!
      expect(logger.level).to eq(Logger::WARN)
      expect(logger.parent_logger.level).to eq(Logger::INFO)
    end

    it "can set the log level to info" do
      logger.info!
      expect(logger.level).to eq(Logger::INFO)
      expect(logger.parent_logger.level).to eq(Logger::INFO)
    end

    it "can set the log level to debug" do
      logger.debug!
      expect(logger.level).to eq(Logger::DEBUG)
      expect(logger.parent_logger.level).to eq(Logger::INFO)
    end
  end

  describe "progname" do
    it "can set a progname" do
      logger = Lumberjack::LocalLogger.new(parent_logger, progname: "TestProgname")
      logger.info("Test message")
      expect(out.string).to include("TestProgname")
    end
  end

  describe "tags" do
    it "can set tags for the logger" do
      logger = Lumberjack::LocalLogger.new(parent_logger, tags: {user: "test_user"})
      logger.info("Test message with tags")
      expect(out.string).to include("test_user")
    end
  end

  describe "logging methods" do
    let(:logger) { Lumberjack::LocalLogger.new(parent_logger, level: :debug) }

    describe "#fatal" do
      it "can log fatal messages" do
        logger.fatal("msg")
        expect(out.string).to include("FATAL")
        expect(out.string).to include("msg")
      end

      it "does not log fatal messages when the level is higher" do
        logger.level = :unknown
        logger.fatal("msg")
        expect(out.string).to be_empty
      end

      it "can log fatal messages with a block" do
        logger.fatal { "msg from block" }
        expect(out.string).to include("FATAL")
        expect(out.string).to include("msg from block")
      end
    end

    describe "#error" do
      it "can log error messages" do
        logger.error("msg")
        expect(out.string).to include("ERROR")
        expect(out.string).to include("msg")
      end

      it "does not log error messages when the level is higher" do
        logger.level = :fatal
        logger.error("msg")
        expect(out.string).to be_empty
      end

      it "can log error messages with a block" do
        logger.error { "msg from block" }
        expect(out.string).to include("ERROR")
        expect(out.string).to include("msg from block")
      end
    end

    describe "#warn" do
      it "can log warn messages" do
        logger.warn("msg")
        expect(out.string).to include("WARN")
        expect(out.string).to include("msg")
      end

      it "does not log warn messages when the level is higher" do
        logger.level = :error
        logger.warn("msg")
        expect(out.string).to be_empty
      end

      it "can log warn messages with a block" do
        logger.warn { "msg from block" }
        expect(out.string).to include("WARN")
        expect(out.string).to include("msg from block")
      end
    end

    describe "#info" do
      it "can log info messages" do
        logger.info("msg")
        expect(out.string).to include("INFO")
        expect(out.string).to include("msg")
      end

      it "does not log info messages when the level is higher" do
        logger.level = :warn
        logger.info("msg")
        expect(out.string).to be_empty
      end

      it "can log info messages with a block" do
        logger.info { "msg from block" }
        expect(out.string).to include("INFO")
        expect(out.string).to include("msg from block")
      end
    end

    describe "#debug" do
      it "can log debug messages" do
        logger.debug("msg")
        expect(out.string).to include("DEBUG")
        expect(out.string).to include("msg")
      end

      it "does not log debug messages when the level is higher" do
        logger.level = :info
        logger.debug("msg")
        expect(out.string).to be_empty
      end

      it "can log debug messages with a block" do
        logger.debug { "msg from block" }
        expect(out.string).to include("DEBUG")
        expect(out.string).to include("msg from block")
      end
    end

    describe "#unknown" do
      it "can log unknown messages" do
        logger.unknown("msg")
        expect(out.string).to include("UNKNOWN")
        expect(out.string).to include("msg")
      end

      it "can log unknown messages with a block" do
        logger.unknown { "msg from block" }
        expect(out.string).to include("UNKNOWN")
        expect(out.string).to include("msg from block")
      end
    end

    describe "#add" do
      it "can add a new log message" do
        logger.add(Logger::INFO, "New log message")
        expect(out.string).to include("INFO")
        expect(out.string).to include("New log message")
      end
    end

    describe "#<<" do
      it "can log messages using the shovel operator" do
        logger << "msg"
        expect(out.string).to include("msg")
      end
    end
  end
end
