#!/usr/bin/env ruby
# frozen_string_literal: true

# Checks that scripts/validate.rb rejects the mistakes it claims to catch.
#
# Each case builds a throwaway copy of the repo's data directory, applies one
# defect, and asserts validation fails with a message mentioning `expect`.

require "English"
require "fileutils"
require "tmpdir"
require "yaml"

ROOT = File.expand_path("..", __dir__)
VALIDATOR = File.join(ROOT, "scripts", "validate.rb")

VALID_TEMPLATE = {
  "id" => "example-setup",
  "title" => "Example Setup",
  "author" => "Test Author",
  "description" => "A minimal but valid setup used by the validator tests.",
  "tags" => ["Solo / single"],
  "categories" => "Income [income]\n- Paycheck [income]\nGroceries\n",
}.freeze

def run_validator(templates, tag_groups = nil)
  Dir.mktmpdir("category-templates-test") do |dir|
    FileUtils.mkdir_p(File.join(dir, "data"))
    FileUtils.mkdir_p(File.join(dir, "scripts"))
    FileUtils.cp(VALIDATOR, File.join(dir, "scripts", "validate.rb"))
    if tag_groups
      File.write(File.join(dir, "data", "tags.yml"), YAML.dump(tag_groups))
    else
      FileUtils.cp(File.join(ROOT, "data", "tags.yml"), File.join(dir, "data", "tags.yml"))
    end
    File.write(File.join(dir, "data", "templates.yml"), YAML.dump(templates))

    output = `ruby #{File.join(dir, "scripts", "validate.rb")} 2>&1`
    [$CHILD_STATUS.success?, output]
  end
end

# Fresh objects every call: YAML.dump emits aliases for shared references, and
# the validator rejects aliases, which would mask the defect under test.
def deep_dup(value)
  case value
  when Hash then value.each_with_object({}) { |(key, nested), copy| copy[deep_dup(key)] = deep_dup(nested) }
  when Array then value.map { |nested| deep_dup(nested) }
  when String then value.dup
  else value
  end
end

def template(overrides = {})
  deep_dup(VALID_TEMPLATE).merge(deep_dup(overrides))
end

CASES = [
  {
    name: "accepts a valid template",
    templates: [template],
    passes: true,
  },
  {
    name: "accepts an optional notes field",
    templates: [template("notes" => "Reviewed annually.")],
    passes: true,
  },
  {
    name: "rejects a missing required field",
    templates: [template.reject { |key, _| key == "author" }],
    expect: "missing required field 'author'",
  },
  {
    name: "rejects an unknown field",
    templates: [template("categoreis" => "typo")],
    expect: "unknown field 'categoreis'",
  },
  {
    name: "rejects a duplicate id",
    templates: [template, template("title" => "Another Setup")],
    expect: "Duplicate id",
  },
  {
    name: "rejects a duplicate title",
    templates: [template, template("id" => "another-setup")],
    expect: "reuses the title",
  },
  {
    name: "rejects a malformed id",
    templates: [template("id" => "Example_Setup")],
    expect: "must be lowercase words",
  },
  {
    name: "rejects an unknown tag",
    templates: [template("tags" => ["Crypto Degens"])],
    expect: "unknown tag",
  },
  {
    name: "rejects an empty tags list",
    templates: [template("tags" => [])],
    expect: "tags must be a non-empty list",
  },
  {
    name: "accepts a template with no tags at all",
    templates: [template.tap { |entry| entry.delete("tags") }],
    passes: true,
  },
  {
    name: "rejects a derived tier claimed as a template tag",
    templates: [template("tags" => ["Comprehensive"])],
    expect: "unknown tag",
  },
  {
    name: "rejects derived tiers that leave a gap",
    templates: [template],
    tags: [
      { "id" => "audience", "label" => "Who it's for", "tags" => ["Solo / single"] },
      { "id" => "style", "label" => "Setup size", "derived" => "category_count", "tags" => [
        { "label" => "Simple", "max" => 39 },
        { "label" => "Comprehensive", "min" => 80 },
      ] },
    ],
    expect: "must be contiguous",
  },
  {
    name: "rejects a first derived tier that sets a minimum",
    templates: [template],
    tags: [
      { "id" => "audience", "label" => "Who it's for", "tags" => ["Solo / single"] },
      { "id" => "style", "label" => "Setup size", "derived" => "category_count", "tags" => [
        { "label" => "Simple", "min" => 10, "max" => 39 },
        { "label" => "Comprehensive", "min" => 40 },
      ] },
    ],
    expect: "must not set 'min'",
  },
  {
    name: "rejects an unknown category property",
    templates: [template("categories" => "Groceries [exclude_from_everything]\n")],
    expect: "unknown property",
  },
  {
    name: "rejects a leading subcategory",
    templates: [template("categories" => "- Paycheck\nGroceries\n")],
    expect: "must be a top-level category",
  },
  {
    name: "rejects duplicate subcategories in one group",
    templates: [template("categories" => "Food\n- Groceries\n- Groceries\n")],
    expect: "duplicates subcategory",
  },
  {
    name: "rejects duplicate top-level categories",
    templates: [template("categories" => "Groceries\nGroceries\n")],
    expect: "duplicates top-level category",
  },
  {
    name: "rejects an over-long description",
    templates: [template("description" => "x" * 241)],
    expect: "max 240",
  },
  {
    name: "accepts the submitter's own account alongside a short description",
    templates: [template("in_their_words" => "We tried a few systems before this one stuck.")],
    passes: true,
  },
  {
    name: "rejects an over-long in_their_words",
    templates: [template("in_their_words" => "x" * 2001)],
    expect: "max 2000",
  },
  {
    name: "rejects a named subcategory with no name",
    templates: [template("categories" => "Food\n- \n")],
    expect: "subcategory with no name",
  },
].freeze

failures = []

CASES.each do |test_case|
  passed, output = run_validator(test_case[:templates], test_case[:tags])

  if test_case[:passes]
    if passed
      puts "  ok   #{test_case[:name]}"
    else
      failures << "#{test_case[:name]}: expected validation to pass, got:\n#{output}"
      puts "  FAIL #{test_case[:name]}"
    end
    next
  end

  if passed
    failures << "#{test_case[:name]}: expected validation to fail, but it passed"
    puts "  FAIL #{test_case[:name]}"
  elsif !output.include?(test_case[:expect])
    failures << "#{test_case[:name]}: expected message containing #{test_case[:expect].inspect}, got:\n#{output}"
    puts "  FAIL #{test_case[:name]}"
  else
    puts "  ok   #{test_case[:name]}"
  end
end

puts
if failures.empty?
  puts "All #{CASES.length} validator tests passed"
  exit 0
end

warn "#{failures.length} of #{CASES.length} validator tests failed:"
failures.each { |failure| warn "\n#{failure}" }
exit 1
