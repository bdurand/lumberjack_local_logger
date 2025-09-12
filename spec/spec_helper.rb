# frozen_string_literal: true

require "stringio"
require "lumberjack/capture_device/rspec"

require_relative "../lib/lumberjack_local_logger"

Lumberjack.deprecation_mode = "raise"
Lumberjack.raise_logger_errors = true

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.default_formatter = "doc" if config.files_to_run.one?
  config.order = :random
  Kernel.srand config.seed
end
