# frozen_string_literal: true

require "stringio"
require "lumberjack/capture_device/rspec"

require_relative "../lib/lumberjack_local_logger"

RSpec.configure do |config|
  config.warnings = true
  config.order = :random
end
