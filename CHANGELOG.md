# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 1.0.1 (unreleased)

### Fixed

- Require the lumberjack gem so the gem can be loaded without lumberjack being required first.
- `add_log_attributes` no longer overrides non-nil default values of optional positional and keyword arguments with nil.
- `add_log_attributes` no longer raises a `SyntaxError` when wrapping methods with no arguments or with an explicit block argument.
- `add_log_attributes` now correctly handles methods with anonymous arguments (`*`, `**`, `&`, `...`).
- `add_log_attributes` can now wrap private and protected methods and preserves their visibility.
- `add_log_attributes` no longer applies the wrong attributes and block when a subclass wraps the same method again.
- Local loggers are now rebuilt when the parent logger changes on a superclass or when `Lumberjack::LocalLogger.default_logger` changes, instead of continuing to use a stale cached logger.
- `setup_logger` now accepts the parent logger as the `from` keyword argument as documented (it was previously a positional argument, so the documented form did not work).
- Building the local logger is now thread safe.
- The Rails railtie only sets the default logger when `Rails.logger` is a Lumberjack logger.

## 1.0.0

### Added

- Initial release
