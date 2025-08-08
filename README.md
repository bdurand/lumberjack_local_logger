# Lumberjack Local Logger

[![Continuous Integration](https://github.com/bdurand/lumberjack_local_logger/actions/workflows/continuous_integration.yml/badge.svg)](https://github.com/bdurand/lumberjack_local_logger/actions/workflows/continuous_integration.yml)
[![Ruby Style Guide](https://img.shields.io/badge/code_style-standard-brightgreen.svg)](https://github.com/testdouble/standard)
[![Gem Version](https://badge.fury.io/rb/lumberjack_local_logger.svg)](https://badge.fury.io/rb/lumberjack_local_logger)

This gem provides a lightweight wrapper around a `Lumberjack::Logger` that allows you to set a different level, progname, and tags. It is useful for scenarios where you want to attach different metadata or have a different logging level for specific parts of your code without affecting the global logger settings or needing to configure multiple loggers.

The `Lumberjack::LocalLogger` acts as a proxy to a parent logger, forwarding all logging calls while applying its own local overrides for level, progname, and tags. This enables you to create contextual loggers that can have different behavior while still writing to the same underlying log destination.

**Key Features:**

- **Local Log Levels**: Set a different logging level for specific components without changing the parent logger
- **Custom Prognames**: Add component-specific program names to identify log sources
- **Contextual Tags**: Attach metadata tags that will be included with all log messages
- **Thread-Safe**: Supports temporary level changes within blocks using thread-local storage
- **Full Logger API**: Implements the complete Ruby Logger interface with proxy support for parent logger methods
- **Zero Configuration**: Works with any existing Lumberjack::Logger instance

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
# Output: [INFO] MyComponent - Processing user data (user_id: 12345, request_id: abc-123)
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
