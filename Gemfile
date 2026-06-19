# frozen_string_literal: true

source "https://rubygems.org"

gemspec

group :development, :test do
  # minitest-snapshot 0.1.0 declares minitest < 6.0, but Ruby 4.0
  # ships minitest 6.0.x as a default gem. Pin to the 5.x line so
  # the constraint resolves.
  gem "minitest", "~> 5.20"
  gem "minitest-snapshot", "~> 0.1"
  gem "rake", "~> 13.0"
end
