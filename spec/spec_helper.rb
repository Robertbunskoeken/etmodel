if ENV["COVERAGE"]
  require 'simplecov'
  SimpleCov.start do
    add_group "Models", "app/models"
    add_group "Controllers", "app/controllers"
  end  
end

require 'rubygems'
require 'spork'

Spork.prefork do
  # Loading more in this block will cause your tests to run faster. However, 
  # if you change any configuration or code from libraries loaded here, you'll
  # need to restart spork for it take effect.
  ENV["RAILS_ENV"] ||= 'test'
  require File.expand_path("../../config/environment", __FILE__)
  require 'rspec/rails'
  require 'authlogic/test_case'
  require 'spork/ext/ruby-debug'

  # Requires supporting ruby files with custom matchers and macros, etc,
  # in spec/support/ and its subdirectories.
  Dir[Rails.root.join("spec/support/**/*.rb")].each {|f| require f}

  RSpec.configure do |config|
    # == Mock Framework
    #
    # If you prefer to use mocha, flexmock or RR, uncomment the appropriate line:
    #
    # config.mock_with :mocha
    # config.mock_with :flexmock
    # config.mock_with :rr
    config.mock_with :rspec

    # Remove this line if you're not using ActiveRecord or ActiveRecord fixtures
    config.fixture_path = "#{::Rails.root}/spec/fixtures"

    # If you're not using ActiveRecord, or you'd prefer not to run each of your
    # examples within a transaction, remove the following line or assign false
    # instead of true.
    config.use_transactional_fixtures = true

    config.include(CustomMatchers)
    config.include(EtmHelper)
    config.include(EtmFixtures)
    config.include(Webrat::Matchers)
    config.include(EtmAuthHelper)
    config.include(Authlogic::TestCase)
  end
  
end

Spork.each_run do
  # This code will be run each time you run your specs.
  FactoryGirl.reload
end
