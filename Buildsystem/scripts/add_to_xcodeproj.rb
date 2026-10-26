#!/usr/bin/env ruby
# frozen_string_literal: true

##
# Registers new source/resource files in VLC.xcodeproj so they are visible to
# Swift/Objective-C and included in the correct build phase.
#
# Why this exists: VLC.xcodeproj uses classic PBXGroup references (not Xcode 16
# "synchronized folders"). A file that is not referenced in the project and in the
# target's build phase will simply not compile.
#
# Usage:
#   ruby Buildsystem/scripts/add_to_xcodeproj.rb \
#     <group-path-relative-to-repo-root> <file> [<file> ...] [--target VLC-iOS]
#
# Examples:
#   ruby Buildsystem/scripts/add_to_xcodeproj.rb Sources/Discourse \
#     DiscourseAPIClient.swift DiscourseModels.swift
#
#   ruby Buildsystem/scripts/add_to_xcodeproj.rb Sources/Discourse/Models \
#     Discourse.swift DiscourseAudio.swift --target VLC-iOS
#
# Files can be given as plain names (resolved inside the group path) or as full
# paths relative to the repo root. The group path must already exist on disk; the
# script creates the matching PBXGroup chain if it does not exist yet.
#
# Extensions map to build phases:
#   .swift .m .mm .c .cpp  -> Sources
#   .xib .storyboard .xcassets .strings .plist .html .json .png .xcprivacy -> Resources
#

require 'xcodeproj'
require 'pathname'

REPO_ROOT = Pathname.new(File.expand_path('../..', __dir__))
PROJECT_PATH = REPO_ROOT.join('VLC.xcodeproj')

SOURCE_EXTENSIONS = %w[.swift .m .mm .c .cc .cpp .h].freeze
# .h files are added as references only (never to a build phase).
HEADER_EXTENSIONS = %w[.h].freeze

def usage
  warn <<~USAGE
    usage: add_to_xcodeproj.rb <group-path> <file> [<file> ...] [--target NAME]
    <group-path> is relative to the repo root, e.g. Sources/Discourse
  USAGE
  exit 1
end

args = ARGV.dup
target_name = 'VLC-iOS'
if (index = args.index('--target'))
  target_name = args[index + 1]
  args.slice!(index, 2)
end

usage if args.length < 2

group_path = args.shift
files = args

project = Xcodeproj::Project.open(PROJECT_PATH.to_s)
target = project.targets.find { |t| t.name == target_name }
abort "error: target '#{target_name}' not found in #{PROJECT_PATH}" unless target

# Find (or create) the PBXGroup chain for group_path, walking from the main group.
def find_or_create_group(project, group_path)
  current = project.main_group
  group_path.split('/').reject(&:empty?).each do |component|
    existing = current.children.find do |child|
      child.is_a?(Xcodeproj::Project::Object::PBXGroup) && (child.display_name == component || child.path == component)
    end
    current = existing || current.new_group(component, component)
  end
  current
end

# Reuse an existing group that already resolves to this directory. Upstream has
# groups such as `Testing` whose path is `Buildsystem/Testing`, so walking by
# component names alone would create a duplicate tree.
def find_group_for_path(project, group_path)
  expected = REPO_ROOT.join(group_path).cleanpath
  project.groups.find do |candidate|
    begin
      Pathname.new(candidate.real_path.to_s).cleanpath == expected
    rescue StandardError
      false
    end
  end
end

group = find_group_for_path(project, group_path) || find_or_create_group(project, group_path)
puts "Using existing group #{group.display_name.inspect}" if group.display_name.to_s != group_path
sources_phase = target.source_build_phase
resources_phase = target.resources_build_phase
abort 'error: no source build phase' unless sources_phase

added = []
files.each do |file|
  file_path = Pathname.new(file)
  file_path = Pathname.new(group_path).join(file) unless file_path.absolute? || file.include?('/')
  absolute = REPO_ROOT.join(file_path)
  unless absolute.file?
    abort "error: file not found: #{absolute}"
  end

  file_name = absolute.basename.to_s
  ext = absolute.extname.downcase

  # If the file already has a reference anywhere in the project, reuse it.
  existing_ref = project.files.find { |f| Pathname.new(f.real_path.to_s) == absolute }
  # `new_reference` resolves relative to the group, so pass the file name only.
  ref = existing_ref || group.new_reference(file_name)

  if HEADER_EXTENSIONS.include?(ext)
    # headers are references only
  elsif SOURCE_EXTENSIONS.include?(ext)
    sources_phase.add_file_reference(ref) unless sources_phase.files_references.include?(ref)
  else
    resources_phase.add_file_reference(ref) unless resources_phase.files_references.include?(ref)
  end

  added << "#{file_name} (ref #{ref.uuid})"
end

project.save
puts "Registered #{added.length} file(s) in target #{target_name} under group #{group_path}:"
added.each { |line| puts "  - #{line}" }
