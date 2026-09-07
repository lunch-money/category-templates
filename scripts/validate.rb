#!/usr/bin/env ruby
# frozen_string_literal: true

# Validates data/templates.yml against the documented schema.
#
# Uses Psych (Ruby's bundled YAML parser), which is the same parser Jekyll uses
# on the marketing site, so a file that passes here will also build there.

require "yaml"
require "set"

ROOT = File.expand_path("..", __dir__)
TEMPLATES_PATH = File.join(ROOT, "data", "templates.yml")
TAGS_PATH = File.join(ROOT, "data", "tags.yml")

REQUIRED_FIELDS = %w[id title author description tags categories].freeze
OPTIONAL_FIELDS = %w[notes].freeze
ALLOWED_FIELDS = (REQUIRED_FIELDS + OPTIONAL_FIELDS).freeze
ALLOWED_PROPERTIES = %w[income exclude_from_budget exclude_from_totals].freeze
ID_PATTERN = /\A[a-z0-9]+(-[a-z0-9]+)*\z/
MAX_DESCRIPTION = 600

class Validator
  attr_reader :errors

  def initialize
    @errors = []
  end

  def error(message)
    @errors << message
  end

  def run
    templates = load_yaml(TEMPLATES_PATH)
    tag_groups = load_yaml(TAGS_PATH)
    return false if @errors.any?

    known_tags = validate_tag_vocabulary(tag_groups)
    return false if @errors.any?

    unless templates.is_a?(Array)
      error("data/templates.yml must be a list of templates")
      return false
    end

    if templates.empty?
      error("data/templates.yml must contain at least one template")
      return false
    end

    seen_ids = Set.new
    seen_titles = Set.new

    templates.each_with_index do |template, index|
      validate_template(template, index, known_tags, seen_ids, seen_titles)
    end

    @errors.empty?
  end

  private

  def load_yaml(path)
    unless File.exist?(path)
      error("Missing required file: #{relative(path)}")
      return nil
    end

    YAML.safe_load_file(path, permitted_classes: [], aliases: false)
  rescue Psych::Exception => e
    error("#{relative(path)} is not valid YAML: #{e.message}")
    nil
  end

  def relative(path)
    path.sub("#{ROOT}/", "")
  end

  def validate_tag_vocabulary(tag_groups)
    unless tag_groups.is_a?(Array)
      error("data/tags.yml must be a list of tag groups")
      return Set.new
    end

    known = Set.new
    tag_groups.each_with_index do |group, index|
      label = "data/tags.yml group ##{index + 1}"

      unless group.is_a?(Hash)
        error("#{label} must be a mapping")
        next
      end

      %w[id label tags].each do |field|
        error("#{label} is missing '#{field}'") unless group[field]
      end

      tags = group["tags"]
      unless tags.is_a?(Array) && tags.all? { |tag| tag.is_a?(String) && !tag.strip.empty? }
        error("#{label} 'tags' must be a list of non-empty strings")
        next
      end

      tags.each do |tag|
        error("data/tags.yml defines '#{tag}' more than once") if known.include?(tag)
        known << tag
      end
    end

    known
  end

  def validate_template(template, index, known_tags, seen_ids, seen_titles)
    position = "templates[#{index}]"

    unless template.is_a?(Hash)
      error("#{position} must be a mapping")
      return
    end

    label = template["id"].is_a?(String) ? "'#{template["id"]}'" : position

    (template.keys - ALLOWED_FIELDS).each do |key|
      error("#{label} has unknown field '#{key}' (allowed: #{ALLOWED_FIELDS.join(", ")})")
    end

    REQUIRED_FIELDS.each do |field|
      value = template[field]
      error("#{label} is missing required field '#{field}'") if value.nil? || (value.respond_to?(:empty?) && value.empty?)
    end

    validate_id(template["id"], position, seen_ids)
    validate_title(template["title"], label, seen_titles)
    validate_text(template["author"], "author", label)
    validate_description(template["description"], label)
    validate_tags(template["tags"], label, known_tags)
    validate_categories(template["categories"], label)
    validate_text(template["notes"], "notes", label) if template.key?("notes")
  end

  def validate_id(id, position, seen_ids)
    return if id.nil?

    unless id.is_a?(String) && id.match?(ID_PATTERN)
      error("#{position} id '#{id}' must be lowercase words separated by single hyphens")
      return
    end

    error("Duplicate id '#{id}' — ids must be unique and stable") if seen_ids.include?(id)
    seen_ids << id
  end

  def validate_title(title, label, seen_titles)
    return if title.nil?

    unless title.is_a?(String) && !title.strip.empty?
      error("#{label} title must be a non-empty string")
      return
    end

    key = title.strip.downcase
    error("#{label} reuses the title '#{title}' — give each setup a distinct name") if seen_titles.include?(key)
    seen_titles << key
  end

  def validate_text(value, field, label)
    return if value.nil?

    error("#{label} #{field} must be a non-empty string") unless value.is_a?(String) && !value.strip.empty?
  end

  def validate_description(description, label)
    return if description.nil?

    unless description.is_a?(String) && !description.strip.empty?
      error("#{label} description must be a non-empty string")
      return
    end

    if description.length > MAX_DESCRIPTION
      error("#{label} description is #{description.length} characters (max #{MAX_DESCRIPTION})")
    end
  end

  def validate_tags(tags, label, known_tags)
    return if tags.nil?

    unless tags.is_a?(Array) && !tags.empty?
      error("#{label} tags must be a non-empty list")
      return
    end

    seen = Set.new
    tags.each do |tag|
      unless tag.is_a?(String)
        error("#{label} has a non-string tag")
        next
      end

      error("#{label} lists the tag '#{tag}' twice") if seen.include?(tag)
      seen << tag

      unless known_tags.include?(tag)
        error("#{label} uses unknown tag '#{tag}' — add it to data/tags.yml or use an existing tag")
      end
    end
  end

  def validate_categories(categories, label)
    return if categories.nil?

    unless categories.is_a?(String)
      error("#{label} categories must be a block string using Lunch Money's import format")
      return
    end

    lines = categories.split("\n").reject { |line| line.strip.empty? }

    if lines.empty?
      error("#{label} categories block is empty")
      return
    end

    if lines.first.start_with?("-")
      error("#{label} starts with a subcategory — the first line must be a top-level category")
    end

    seen_paths = Set.new
    current_parent = nil

    lines.each_with_index do |raw_line, line_index|
      location = "#{label} line #{line_index + 1}"

      if raw_line != raw_line.rstrip
        error("#{location} has trailing whitespace")
      end

      line = raw_line.strip
      is_child = line.start_with?("-")
      name_and_properties = is_child ? line.sub(/\A-\s*/, "") : line

      if is_child && name_and_properties.empty?
        error("#{location} is a subcategory with no name")
        next
      end

      name, properties = split_properties(name_and_properties, location)
      next if name.nil?

      if name.empty?
        error("#{location} has no category name")
        next
      end

      properties.each do |property|
        unless ALLOWED_PROPERTIES.include?(property)
          error("#{location} has unknown property '#{property}' (allowed: #{ALLOWED_PROPERTIES.join(", ")})")
        end
      end

      if properties.uniq.length != properties.length
        error("#{location} repeats a property")
      end

      if is_child
        path = "#{current_parent}\u0000#{name.downcase}"
        error("#{location} duplicates subcategory '#{name}' within the same group") if seen_paths.include?(path)
        seen_paths << path
      else
        current_parent = name.downcase
        path = "\u0000#{name.downcase}"
        error("#{location} duplicates top-level category '#{name}'") if seen_paths.include?(path)
        seen_paths << path
      end
    end
  end

  def split_properties(text, location)
    match = text.match(/\A(.*?)\s*\[([^\[\]]*)\]\s*\z/)
    return [text.strip, []] unless match

    remainder = match[1]
    if remainder.include?("[") || remainder.include?("]")
      error("#{location} has malformed square brackets — use a single [property, property] group at the end")
      return [nil, nil]
    end

    properties = match[2].split(",").map(&:strip).reject(&:empty?)
    if properties.empty?
      error("#{location} has an empty property group")
      return [nil, nil]
    end

    [remainder.strip, properties]
  end
end

validator = Validator.new
if validator.run
  templates = YAML.safe_load_file(TEMPLATES_PATH)
  puts "OK: #{templates.length} templates passed validation"
  exit 0
end

warn "Validation failed:"
validator.errors.each { |message| warn "  - #{message}" }
warn "\nSee CONTRIBUTING.md for the expected format."
exit 1
