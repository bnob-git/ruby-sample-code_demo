# frozen_string_literal: true

ENV["RACK_ENV"] = "test"
ENV["IDME_BASE_URL"] = "http://localhost:4568"
ENV["IDME_CLIENT_ID"] = "test-client"
ENV["IDME_CLIENT_SECRET"] = "test-secret"
ENV["IDME_REDIRECT_URI"] = "http://localhost:4567/callback"
ENV["SESSION_SECRET"] = "x" * 64

require "cgi"
require "rack/test"
require "webmock/rspec"
require_relative "../app"
require_relative "../mock_idme"

RSpec.configure do |config|
  config.include Rack::Test::Methods
  config.disable_monkey_patching!
  config.order = :random

  # Route the app's outbound OAuth requests to the in-process mock ID.me.
  config.before do
    stub_request(:any, %r{\Ahttp://localhost:4568/}).to_rack(MockIdme)
  end
end
