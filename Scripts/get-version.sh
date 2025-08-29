#!/usr/bin/env ruby
require 'bundler/setup'
require 'xcodeproj'

# setup paths for the project
repo_root = Dir.pwd
project_path = File.expand_path('Convos.xcodeproj', repo_root)

# ensure project exists
unless File.exist?(project_path)
  abort("❌ Error: Xcode project not found at #{project_path}")
end

# Get current version from Xcode project (marketing version only)
# Note: Build numbers are automatically incremented and injected by Bitrise using $BITRISE_BUILD_NUMBER at build time
def get_version(project_path)
  project = Xcodeproj::Project.open(project_path)

  # Get versions from all targets
  versions = {}

  project.targets.each do |target|
    target.build_configurations.each do |config|
      if config.build_settings.key?('MARKETING_VERSION')
        version = config.build_settings['MARKETING_VERSION']
        versions[target.name] ||= []
        versions[target.name] << version
      end
    end
  end

  if versions.empty?
    abort("❌ Error: MARKETING_VERSION not found in any target's settings")
  end

  # Check if all versions match
  all_versions = versions.values.flatten.uniq
  if all_versions.size > 1
    puts "❌ Version mismatch detected:"
    versions.each do |target, target_versions|
      puts "  📱 #{target}: #{target_versions.uniq.join(', ')}"
    end
    abort("Error: All targets must have the same version number")
  end

  # Return only the marketing version (no build number)
  # Build numbers are handled by Bitrise using $BITRISE_BUILD_NUMBER at build time
  all_versions.first
end

# print the version
begin
  version = get_version(project_path)
  # Only print the version number (clean output for scripts)
  puts version
rescue => e
  puts "❌ Error getting version: #{e.message}"
  exit 1
end
