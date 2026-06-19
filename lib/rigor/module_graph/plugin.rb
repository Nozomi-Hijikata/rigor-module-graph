# frozen_string_literal: true

# Lazy plugin entry point.
#
# This file is `require`d by `lib/rigor-module-graph.rb`, which itself
# is `require`d two distinct ways:
#
# 1. From `Rigor::Plugin::Loader` when a host project's `.rigor.yml`
#    lists `rigor-module-graph` under `plugins:` — the host gem has
#    `rigortype` already loaded, so we want to subclass
#    `Rigor::Plugin::Base` and register at require-time.
# 2. From the `rigor-module-graph` CLI when the user only wants the
#    converter subcommands (`dot`, `mermaid`, `cycles`) — `rigortype`
#    may not be available and we must NOT crash.
#
# We detect which mode we're in and defer the Rigor wiring to the
# concrete subclass file when appropriate.

require_relative "edge"
require_relative "analyzer"
require_relative "constant_name"

if defined?(Rigor::Plugin::Base)
  require_relative "plugin/rigor_plugin"
end
