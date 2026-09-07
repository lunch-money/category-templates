#!/usr/bin/env ruby
# frozen_string_literal: true

# Renders the Jekyll data files consumed by the marketing site's
# /category-templates page.
#
#   ruby scripts/render-marketing-data.rb path/to/marketing-site
#
# Output is byte-for-byte deterministic: the sync workflow diffs it against the
# committed copies and only opens a pull request when something actually changed.

require "yaml"

ROOT = File.expand_path("..", __dir__)
SOURCE_REPO = "lunch-money/category-templates"

OUTPUTS = {
  "data/templates.yml" => "_data/category_templates.yml",
  "data/tags.yml" => "_data/category_template_tags.yml",
}.freeze

destination = ARGV[0]
if destination.nil? || destination.empty?
  warn "usage: ruby scripts/render-marketing-data.rb <path-to-marketing-site>"
  exit 1
end

unless File.directory?(File.join(destination, "_data"))
  warn "#{destination} does not look like the marketing site: no _data directory"
  exit 1
end

def header(source_path)
  <<~HEADER
    #
    # GENERATED FILE — do not edit manually.
    # Source: #{SOURCE_REPO}/#{source_path}
    #
    # To update entries: edit #{source_path} in the #{SOURCE_REPO} repository.
    # Changes are applied automatically when that repo merges to main.
    #
  HEADER
end

OUTPUTS.each do |source_path, target_path|
  source = File.join(ROOT, source_path)
  target = File.join(destination, target_path)

  # Round-tripping through Psych normalises formatting, so an unrelated
  # whitespace change upstream cannot produce a noisy diff downstream.
  data = YAML.safe_load_file(source, permitted_classes: [], aliases: false)
  rendered = "#{header(source_path)}#{YAML.dump(data)}"

  if File.exist?(target) && File.read(target) == rendered
    puts "unchanged  #{target_path}"
    next
  end

  File.write(target, rendered)
  puts "written    #{target_path}"
end
