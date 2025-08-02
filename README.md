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
  level: :debug,
  progname: "MyComponent",
  tags: { user_id: 12345, request_id: "abc-123" }
)

# The local logger can log debug messages even though parent is set to info
local_logger.debug("This will appear in the log")  # ✓ Logs with debug level
parent_logger.debug("This will not appear")        # ✗ Filtered out by parent's info level

local_logger.info("Processing user data")
# Output: [INFO] MyComponent - Processing user data (user_id: 12345, request_id: abc-123)
```

### Use Cases

#### 1. Component-Specific Logging Levels

Perfect for debugging specific parts of your application without flooding logs:

```ruby
# Main application logger at INFO level
app_logger = Lumberjack::Logger.new("app.log", level: :info)

# Enable debug logging only for the database component
db_logger = Lumberjack::LocalLogger.new(app_logger, level: :debug, progname: "Database")

class DatabaseConnection
  def initialize
    @logger = db_logger
  end

  def execute_query(sql)
    @logger.debug("Executing SQL: #{sql}")  # Only shows when debugging DB issues
    @logger.info("Query completed successfully")
  end
end
```

#### 2. Request Context Logging

Add request-specific metadata to all log messages:

```ruby
class RequestHandler
  def initialize(request_id:, user_id:)
    @logger = Lumberjack::LocalLogger.new(
      Rails.logger,
      progname: "RequestHandler",
      tags: {
        request_id: request_id,
        user_id: user_id,
        session_id: SecureRandom.hex(8)
      }
    )
  end

  def process_request
    @logger.info("Starting request processing")
    # All subsequent log messages will include the request context
    @logger.warn("Rate limit approaching") if rate_limit_check
    @logger.info("Request completed successfully")
  end
end
```

#### 3. Temporary Log Level Changes

Temporarily change logging levels for specific operations:

```ruby
logger = Lumberjack::LocalLogger.new(parent_logger, level: :info)

# Temporarily enable debug logging for a complex operation
logger.with_level(:debug) do
  perform_complex_calculation  # All debug messages in this block will be logged
end

# Or silence noisy operations
logger.silence do
  bulk_import_data  # Only ERROR and FATAL messages will be logged
end
```

#### 4. Service-Oriented Architecture

Different services can have their own logging context:

```ruby
class UserService
  def initialize
    @logger = Lumberjack::LocalLogger.new(
      Application.logger,
      progname: "UserService",
      tags: { service: "user", version: "1.2.3" }
    )
  end

  def create_user(params)
    @logger.info("Creating new user")
    # Implementation...
    @logger.info("User created successfully", tags: { user_id: user.id })
  end
end

class PaymentService
  def initialize
    @logger = Lumberjack::LocalLogger.new(
      Application.logger,
      level: :warn,  # More restrictive logging for sensitive operations
      progname: "PaymentService",
      tags: { service: "payment", compliance: "pci-dss" }
    )
  end
end
```

#### 5. Background Job Logging

Add job-specific context to background job logs:

```ruby
class EmailWorker
  def perform(job_id, recipient_email)
    @logger = Lumberjack::LocalLogger.new(
      Sidekiq.logger,
      progname: "EmailWorker",
      tags: {
        job_id: job_id,
        recipient: recipient_email,
        worker: self.class.name
      }
    )

    @logger.info("Starting email job")
    send_email(recipient_email)
    @logger.info("Email sent successfully")
  rescue => e
    @logger.error("Email job failed: #{e.message}")
    raise
  end
end
```

### API Reference

```ruby
# Initialize a local logger
local_logger = Lumberjack::LocalLogger.new(
  parent_logger,           # Required: The parent Lumberjack::Logger
  level: :debug,           # Optional: Local log level override
  progname: "MyApp",       # Optional: Program name for log messages
  tags: { key: "value" }   # Optional: Hash of tags to add to messages
)

# All standard Logger methods are available
local_logger.debug("Debug message")
local_logger.info("Info message")
local_logger.warn("Warning message")
local_logger.error("Error message")
local_logger.fatal("Fatal message")

# Level checking methods
local_logger.debug?  # => true/false
local_logger.info?   # => true/false

# Level setting methods
local_logger.debug!   # Set level to debug
local_logger.info!    # Set level to info
local_logger.level = :warn  # Set custom level

# Temporary level changes
local_logger.with_level(:debug) { ... }
local_logger.silence { ... }  # Sets to ERROR level temporarily
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
