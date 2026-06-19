# frozen_string_literal: true

require_relative "../../test_helper"
require "fileutils"
require "tmpdir"

class PackwerkOverlayTest < Minitest::Test
  PackwerkOverlay = Rigor::ModuleGraph::PackwerkOverlay
  Edge = Rigor::ModuleGraph::Edge

  def test_discover_returns_empty_when_no_package_yml
    Dir.mktmpdir do |tmp|
      FileUtils.mkdir_p(File.join(tmp, "app/models"))
      overlay = PackwerkOverlay.discover(tmp)
      refute_predicate overlay, :any?
      assert_empty overlay.packages
    end
  end

  def test_discover_finds_nested_packages_and_names_them
    Dir.mktmpdir do |tmp|
      FileUtils.mkdir_p(File.join(tmp, "packages/billing/app/models"))
      FileUtils.mkdir_p(File.join(tmp, "packages/auth/app/models"))
      File.write(File.join(tmp, "packages/billing/package.yml"), "")
      File.write(File.join(tmp, "packages/auth/package.yml"), "")

      overlay = PackwerkOverlay.discover(tmp)
      names = overlay.packages.map(&:name).sort
      assert_equal %w[packages/auth packages/billing], names
    end
  end

  def test_root_package_yml_resolves_to_dot
    Dir.mktmpdir do |tmp|
      File.write(File.join(tmp, "package.yml"), "")
      overlay = PackwerkOverlay.discover(tmp)
      assert_equal ["."], overlay.packages.map(&:name)
    end
  end

  def test_package_for_picks_deepest_match
    Dir.mktmpdir do |tmp|
      FileUtils.mkdir_p(File.join(tmp, "packages/billing/invoices/app"))
      File.write(File.join(tmp, "packages/billing/package.yml"), "")
      File.write(File.join(tmp, "packages/billing/invoices/package.yml"), "")

      overlay = PackwerkOverlay.discover(tmp)
      target = File.join(tmp, "packages/billing/invoices/app/invoice.rb")
      FileUtils.mkdir_p(File.dirname(target))
      File.write(target, "")

      assert_equal "packages/billing/invoices", overlay.package_for(target)&.name
    end
  end

  def test_package_for_returns_nil_outside_any_package
    Dir.mktmpdir do |tmp|
      FileUtils.mkdir_p(File.join(tmp, "packages/billing"))
      FileUtils.mkdir_p(File.join(tmp, "lib"))
      File.write(File.join(tmp, "packages/billing/package.yml"), "")
      File.write(File.join(tmp, "lib/something.rb"), "")

      overlay = PackwerkOverlay.discover(tmp)
      assert_nil overlay.package_for(File.join(tmp, "lib/something.rb"))
    end
  end

  def test_groups_for_maps_node_names_via_first_seen_path
    Dir.mktmpdir do |tmp|
      FileUtils.mkdir_p(File.join(tmp, "packages/billing"))
      FileUtils.mkdir_p(File.join(tmp, "packages/auth"))
      File.write(File.join(tmp, "packages/billing/package.yml"), "")
      File.write(File.join(tmp, "packages/auth/package.yml"), "")

      edges = [
        Edge.build(from: "Billing::Invoice", to: "ApplicationRecord",
                   kind: "inherits",
                   path: File.join(tmp, "packages/billing/invoice.rb")),
        Edge.build(from: "Auth::User", to: "ApplicationRecord",
                   kind: "inherits",
                   path: File.join(tmp, "packages/auth/user.rb"))
      ]
      overlay = PackwerkOverlay.discover(tmp)
      groups = overlay.groups_for(edges)
      assert_equal "packages/billing", groups["Billing::Invoice"]
      assert_equal "packages/auth", groups["Auth::User"]
      # ApplicationRecord lives outside any package — no entry.
      refute_includes groups.keys, "ApplicationRecord"
    end
  end

  def test_discover_prunes_known_noise_directories
    Dir.mktmpdir do |tmp|
      # A bogus package.yml inside node_modules / .git / vendor
      # must not surface as a real package.
      %w[node_modules .git vendor tmp log].each do |noise|
        FileUtils.mkdir_p(File.join(tmp, noise, "fake"))
        File.write(File.join(tmp, noise, "fake/package.yml"), "")
      end
      File.write(File.join(tmp, "package.yml"), "")
      overlay = PackwerkOverlay.discover(tmp)
      assert_equal ["."], overlay.packages.map(&:name)
    end
  end
end
