require 'rspec'
require 'logging'
require 'rspec/logging_helper'

RSpec.configure do |config|
    include RSpec::LoggingHelper
    config.capture_log_messages
end

Logging.logger.root.level = :debug
Logging.logger.root.appenders = Logging.appenders.syslog('rspec')
