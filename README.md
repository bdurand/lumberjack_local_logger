# Lumberjack Local Logger

[![Continuous Integration](https://github.com/bdurand/lumberjack_local_logger/actions/workflows/continuous_integration.yml/badge.svg)](https://github.com/bdurand/lumberjack_local_logger/actions/workflows/continuous_integration.yml)
[![Ruby Style Guide](https://img.shields.io/badge/code_style-standard-brightgreen.svg)](https://github.com/testdouble/standard)
[![Gem Version](https://badge.fury.io/rb/lumberjack_local_logger.svg)](https://badge.fury.io/rb/lumberjack_local_logger)

This gem provides a mechanism for setting up a logger for local code that inherits from a parent logger. The local logger will output to the same destination as the parent logger but can set a different level, progname, and attributes. It is useful for scenarios where you want to attach different metadata or have a different logging level for specific parts of your code without affecting the global logger settings or needing to configure multiple loggers.

This gem requires the [lumberjack](https://github.com/bdurand/lumberjack) gem.

## Usage

### Basic Setup

First, configure the default logger for the gem (typically in an initializer):

```ruby
# In a Rails application, add this to an initializer (e.g., config/initializers/logging.rb)
Lumberjack::LocalLogger.default_logger = Rails.logger

# Or for a standalone application
require 'lumberjack'
require 'lumberjack_local_logger'
Lumberjack::LocalLogger.default_logger = Lumberjack::Logger.new(STDOUT)
```

### Including LocalLogger in Your Classes

Include the `Lumberjack::LocalLogger` module in your class and configure the local logger:

```ruby
class UserService
  include Lumberjack::LocalLogger

  # Configure the local logger for this class
  setup_logger do |logger|
    logger.level = :info
    logger.progname = "UserService"
    logger.tag!(component: "user_management", service: "user_service")
  end

  def create_user(email, name)
    user = User.create!(email: email, name: name)

    # Log entries will include the metadata set in setup_logger
    logger.info("User created successfully", user_id: user.id)

    user
  end
end
```

### Setting Parent Logger for Specific Classes

You can set a different parent logger for specific classes instead of using the default. The parent logger will be inherited by the local logger and used as the base for all logging operations.

```ruby
class DatabaseService
  include Lumberjack::LocalLogger

  # Set a specific parent logger for this class
  self.parent_logger = Lumberjack::Logger.new("db.log", level: :debug)

  setup_logger do |logger|
    logger.progname = "DatabaseService"
    logger.tag!(component: "database")
  end
end

# Alternatively, you can set the parent logger in the setup_logger call with the `from` option.
class AnalyticsService
  include Lumberjack::LocalLogger

  setup_logger(from: Database.logger) do |logger|
    logger.progname = "AnalyticsService"
    logger.tag!(component: "analytics")
  end
end
```

### Separating Logging Setup from Business Logic

Use `add_log_attributes` to automatically add metadata to all log entries within a specific method. This can be useful for keeping logging concerns separate from business logic.

```ruby
class PaymentService
  include Lumberjack::LocalLogger

  def process_payment(amount, currency, payment_method)
    # These log entries will include the metadata set in add_log_attributes.
    logger.info("Starting payment processing")

    result = charge_payment(amount, currency, payment_method)

    logger.info("Payment processed")
    result
  end

  # Add attributes to all log entries in the process_payment method. A new log context
  # will be created with these attributes set for the duration of the method call.
  # Any log entries made with the local logger will include these attributes
  # until the method exits.
  # NOTE: The method must be defined before calling add_log_attributes.
  add_log_attributes(:process_payment, payment_flow: "standard", version: "v2")

  private

  def charge_payment(amount, currency, payment_method)
    payment = Payment.new(amount: amount, currency: currency, method: payment_method)

    # This log entry will also include the attributes added by add_log_attributes
    # when it is called from the `process_payment` method.
    logger.info("Charged payment", charge_id: payment.charge_id, status: payment.status)

    { status: payment.status, charge_id: payment.charge_id }
  end
end
```

You can also provide a block to the `add_log_attributes` method to set further attributes on the logger. The block will be called with the same arguments as the specified method.

```ruby
class UserPaymentService
  include Lumberjack::LocalLogger

  attr_reader :user_id

  def initialize(user_id)
    @user_id = user_id
  end

  def process_payment(amount, currency, payment_method)
    ...
  end

  # NOTE: The method must be defined before calling add_log_attributes.
  add_log_attributes(:process_payment) do |amount, currency, payment_method|
    logger.tag(
      amount: amount,
      currency: currency,
      payment_method: payment_method,
      user_id: user_id # You can also call instance methods from the block
    )
  end
end
```

### Inheritance and Logger Hierarchy

Local loggers work with class inheritance. Child classes inherit the parent logger configuration and can extend it:

```ruby
class BaseService
  include Lumberjack::LocalLogger

  setup_logger do |logger|
    logger.progname = "BaseService"
    logger.tag!(app: "MyApp")
  end
end

class EmailService < BaseService
  # Inherits the parent logger and adds additional configuration
  setup_logger do |logger|
    logger.tag!(service: "EmailService")
    logger.level = :debug
    logger.progname = "EmailService"
  end

  def send_email(to, subject)
    # This will log with both app: "MyApp" and service: "EmailService" attributes
    logger.debug("Sending email", to: to, subject: subject)
  end
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
