# Lumberjack Local Logger

[![Continuous Integration](https://github.com/bdurand/lumberjack_local_logger/actions/workflows/continuous_integration.yml/badge.svg)](https://github.com/bdurand/lumberjack_local_logger/actions/workflows/continuous_integration.yml)
[![Ruby Style Guide](https://img.shields.io/badge/code_style-standard-brightgreen.svg)](https://github.com/testdouble/standard)
[![Gem Version](https://badge.fury.io/rb/lumberjack_local_logger.svg)](https://badge.fury.io/rb/lumberjack_local_logger)

This gem provides a lightweight wrapper around a `Lumberjack::Logger` from the [lumberjack](https://github.com/bdurand/lumberjack) gem that allows you to set a different level, progname, and tags. It is useful for scenarios where you want to attach different metadata or have a different logging level for specific parts of your code without affecting the global logger settings or needing to configure multiple loggers.

The `Lumberjack::LocalLogger` acts as a proxy to a parent logger, forwarding all logging calls while applying its own local overrides for level, progname, and tags. This enables you to create contextual loggers that can have different behavior while still writing to the same underlying log destination.

**Key Features:**

- **Local Log Levels**: Set a different logging level for specific components without changing the parent logger.
- **Contextual Tags**: Attach metadata tags that will be included with all log messages.
- **Custom Prognames**: Add component-specific program names to identify log sources.
- **Thread-Safe**: Supports temporary level changes within blocks using thread-local storage.
- **Full Logger API**: Implements the complete Ruby Logger interface with proxy support for parent logger methods.
- **Zero Configuration**: Works with any existing Lumberjack::Logger instance.
- **Helper Module**: Provides a convenient way to set up local loggers in your classes and isolate logging metadata from business logic.

## Usage

### Basic Example

```ruby
require "lumberjack"
require "lumberjack_local_logger"

# Create a parent logger
parent_logger = Lumberjack::Logger.new(STDOUT, level: :info)

# Create a local logger with different settings
local_logger = Lumberjack::LocalLogger.new(
  parent_logger,
  level: :debug, # Optional; sets the level just for this logger
  progname: "MyComponent", # Optional; sets a different program name
  tags: { user_id: 12345, request_id: "abc-123" } # Optional; adds tags to all messages
)

# The local logger can log debug messages even though parent is set to info
local_logger.debug("This will appear in the log")  # ✓ Logs with debug level
parent_logger.debug("This will not appear")        # ✗ Filtered out by parent's info level

# Meta data is included in all log messages
local_logger.info("Processing user data")
# Output will include the progname and tags in the log entry
```

### Extended Example: Overriding The Local Log Level

A use case for a local logger is to provide a different log level for specific parts of your application without affecting the global logger settings. This is particularly useful in scenarios where you want to increase the verbosity of logging for debugging purposes in a specific component or module.

> [!NOTE]
> This example uses the [super_settings](https://github.com/bdurand/super_settings) gem to provide a runtime value to control the log level.

```ruby
# Module that adds a local logger to a class. The logger can dynamically have debug logging
# turned on by adding the class name to the debug_logs_enabled setting.
module LocalLogging
  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def logger
      @local_logger ||= Lumberjack::LocalLogger.new(Application.logger)
    end

    def with_local_log_level(&block)
      level = :debug if SuperSettings.array("debug_logs_enabled", []).include?(name)
      logger.with_local_level(level, &block)
    end
  end

  def logger
    self.class.logger
  end

  def with_local_log_level(&block)
    self.class.with_local_log_level(&block)
  end
end

class MyService
  include LocalLogging

  def initialize(params)
    @params = params
  end

  def perform
    with_local_log_level do
      # Debug logs can enabled dynamically but only for these log statements.
      logger.debug("Performing action with #{@params.inspect}")

      # Anything logged in this class will use the regular log level.
      result = ResultFetcher.new(params).result

      logger.debug("Got result: #{result.inspect}")

      # The local logger level will still be set inside this local method
      process_result(result)
    end
  end

  private

  def process_result(result)
    # Process the result here
  end
end
```

### Local Log Helper

The Local Log Helper provides a convenient way to add logging functionality to your classes. By including the `Lumberjack::LocalLogger::Helper` module, you can easily set up a local logger with custom settings.

First, you need to set up a default logger (typically in an initializer):

```ruby
# In a Rails application, add this to config/initializers/logging.rb:
Lumberjack::LocalLogger::Helper.default_logger = Rails.logger

# Or for non-Rails applications:
Lumberjack::LocalLogger::Helper.default_logger = Lumberjack::Logger.new(STDOUT)
```

Then you can use the helper in your classes:

```ruby
class MyClass
  include Lumberjack::LocalLogger::Helper

  # Set tags that will be recorded on all log entries made in this class.
  self.logger_tags = {component: "MyClass"}

  # Set a logger level for the logger on this class. This will override the default logger level.
  self.logger_level = :info

  def initialize(action_name)
    @action = action_name
  end

  def perform(user_id, roles: [])
    logger.info("Performing action #{@action} for user #{user_id}")
    OtherClass.new(user_id, roles).perform
  end

  # This method wraps the `perform` with log tags. The "method" tag will
  # be added to the local logger for the duration of each method call while
  # the "topic" tag will be added to the parent logger for the duration of
  # the method call.
  add_log_tags_to_method(:perform, local_tags: {method: "perform"}, global_tags: {topic: "my_class"}) do |user_id, roles:|
    # The optional block will be called with the original method arguments.

    # Add user_id and roles to all log entries for the duration of the method call
    logger.tag(user_id: user_id, roles: roles)

    # Add the instance action only to local logger entries for the duration of the method call.
    # Within the block you can call instance methods and access instance variables.
    logger.tag_local(action: @action)
  end
end
```

### Adding Local Tags

You can add tags to your local logger in several ways:

#### Permanent Tags

In addition to the tags set up on the constructor, you can also add more tags with `add_local_tags`.

```ruby
# Add tags permanently to the logger instance
local_logger.add_local_tags(service: "user_service", version: "1.2")

# Remove specific tags
local_logger.remove_local_tags(:version)
```

#### Temporary Tags with Blocks

You can call `tag_local` with a block to temporarily add tags for the duration of the block.

```ruby
local_logger.tag_local(request_id: "abc-123") do
  local_logger.info("Processing request")  # Will include request_id tag
end
```

Calls to `tag_local` can be nested.

```ruby
local_logger.tag_local(user_id: 123) do
  local_logger.tag_local(action: "update") do
    local_logger.info("User action")  # Will include both user_id and action tags
  end
end
```

Calling `tag_local` without a block will add the tags to the current block. If there is not a current `tag_local` block then no tags will be added.

```ruby
local_logger.tag_local(action: "update") do
  local_logger.tag(user_id: 123)
  local_logger.info("User action")  # Will include both user_id and action tags
end
```

## Installation

Add this line to your application's Gemfile:

```ruby
gem "lumberjack_local_logger"
```

And then execute:
```bash
$ bundle install
```

Or install it yourself as:
```bash
$ gem install lumberjack_local_logger
```

## Contributing

Open a pull request on GitHub.

Please use the [standardrb](https://github.com/testdouble/standard) syntax and lint your code with `standardrb --fix` before submitting.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
