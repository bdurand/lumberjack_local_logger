# frozen_string_literal: true

ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" if File.exist?(ENV["BUNDLE_GEMFILE"])

require "stringio"

begin
  require "simplecov"
  SimpleCov.start do
    skip ["/spec/"]
  end
rescue LoadError
end

Bundler.require(:default, :test)

require "lumberjack/capture_device/rspec"

require_relative "../lib/lumberjack_local_logger"

Lumberjack.deprecation_mode = :raise
Lumberjack.raise_logger_errors = true

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.default_formatter = "doc" if config.files_to_run.one?
  config.order = :random
  Kernel.srand config.seed
end
