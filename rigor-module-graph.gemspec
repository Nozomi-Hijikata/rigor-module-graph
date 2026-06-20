# frozen_string_literal: true

require_relative "lib/rigor/module_graph/version"

Gem::Specification.new do |spec|
  spec.name = "rigor-module-graph"
  spec.version = Rigor::ModuleGraph::VERSION
  spec.authors = ["Nozomi Hijikata"]
  spec.email = ["b8yukifsukeo999n@gmail.com"]

  spec.summary = "Class/module/constant dependency graph for Ruby projects, built on Rigor."
  spec.description = <<~DESC
    Rigor plugin and CLI that extract Ruby class/module/constant dependencies
    (inheritance, include/prepend/extend, constant references) and emit
    Graphviz DOT, SVG, and Mermaid output. The class/module-level
    counterpart to Packwerk/Graphwerk.
  DESC
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0.0", "< 4.1"

  spec.files = Dir[
    "lib/**/*.rb",
    "lib/**/*.erb",
    "lib/**/templates/**/*.{css,js}",
    "lib/**/templates/vendor/CHECKSUMS",
    "exe/*",
    "README.md",
    "CHANGELOG.md",
    "LICENSE.txt"
  ]
  spec.bindir = "exe"
  spec.executables = ["rigor-module-graph"]
  spec.require_paths = ["lib"]
  spec.metadata = {
    "documentation_uri" => "https://rubydoc.info/gems/rigor-module-graph",
    "changelog_uri" => "https://github.com/nozomemein/rigor-module-graph/blob/main/CHANGELOG.md",
    "source_code_uri" => "https://github.com/nozomemein/rigor-module-graph",
    "bug_tracker_uri" => "https://github.com/nozomemein/rigor-module-graph/issues",
    "homepage_uri" => "https://github.com/nozomemein/rigor-module-graph",
    "rubygems_mfa_required" => "true"
  }
  spec.rdoc_options = ["--main", "README.md", "--markup", "markdown"]
  spec.extra_rdoc_files = ["README.md"]

  spec.add_dependency "rigortype", "~> 0.2.1"
  # rigortype 0.2.1 declares rbs >= 3.0, < 5.0, but uses an API
  # (`RBS::Environment::ClassEntry#each_decl`) that only exists in
  # rbs 4.x. The stdlib-bundled rbs in Ruby 4.0 is 3.10, so we pin
  # explicitly to keep the analyzer alive.
  spec.add_dependency "rbs", "~> 4.0"
end
