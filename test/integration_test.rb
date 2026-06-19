# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
require "open3"
require "tmpdir"

# End-to-end: drive the real `rigor` binary against a tiny Rails-
# shaped fixture, run `rigor-module-graph collect`, and snapshot
# the resulting edges JSONL. This is the test that catches
# breakage of the plugin's wiring against rigortype releases.
class IntegrationTest < Minitest::Test
  include SnapshotHelpers

  FIXTURE = File.expand_path("fixtures/rails_app", __dir__)
  GEM_ROOT = File.expand_path("..", __dir__)

  def test_collect_emits_expected_edges
    skip "rigor binary not on PATH" unless rigor_available?

    Dir.mktmpdir("rigor-module-graph-int") do |tmp|
      copy_fixture(tmp)
      run_collect(tmp)
      edges_file = File.join(tmp, ".rigor/module_graph/edges.jsonl")
      assert_path_exists edges_file, "expected #{edges_file} to be written"
      assert_snapshot "integration/edges", normalised(edges_file, tmp)
    end
  end

  def test_collect_is_idempotent
    skip "rigor binary not on PATH" unless rigor_available?

    Dir.mktmpdir("rigor-module-graph-int") do |tmp|
      copy_fixture(tmp)
      run_collect(tmp)
      first = File.read(File.join(tmp, ".rigor/module_graph/edges.jsonl"))
      run_collect(tmp)
      second = File.read(File.join(tmp, ".rigor/module_graph/edges.jsonl"))
      assert_equal first, second, "second collect run produced different edges"
    end
  end

  def rigor_available?
    !`which rigor`.strip.empty?
  end

  def copy_fixture(tmp)
    FileUtils.cp_r(File.join(FIXTURE, "."), tmp)
  end

  def run_collect(cwd)
    env = { "BUNDLE_GEMFILE" => File.join(GEM_ROOT, "Gemfile") }
    exe = File.join(GEM_ROOT, "exe/rigor-module-graph")
    out, err, status = Open3.capture3(env, "bundle", "exec", exe, "collect", chdir: cwd)
    return if status.success?

    flunk "collect failed (exit #{status.exitstatus})\nSTDOUT:\n#{out}\nSTDERR:\n#{err}"
  end

  # Strip volatile bits before snapshotting:
  # - Sort lines so worker ordering doesn't matter.
  # - Replace absolute paths with their fixture-relative form so
  #   tmpdir randomness doesn't leak into the snapshot. macOS
  #   tmpdir paths come back with a `/private` realpath prefix in
  #   diagnostics, so we strip both forms.
  def normalised(path, tmp)
    real_tmp = File.realpath(tmp)
    lines = File.readlines(path).map(&:strip)
    lines.map! do |line|
      line.gsub(real_tmp + "/", "").gsub(tmp + "/", "")
    end
    lines.sort.join("\n") + "\n"
  end
end
