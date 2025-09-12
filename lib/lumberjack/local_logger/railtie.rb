# frozen_string_literal: true

module Lumberjack
  class LocalLogger::Railtie < ::Rails::Railtie
    initializer "lumberjack_local_logger" do
      Lumberjack::LocalLogger.default_logger = Rails.logger
    end
  end
end
