#!/usr/bin/env ruby
require 'bundler/setup'
require 'xcodeproj'

# setup paths for the project
repo_root = Dir.pwd
project_path = File.expand_path('Convos.xcodeproj', repo_root)

# ensure project exists
unless File.exist?(project_path)
  abort("Error: Xcode project not found at #{project_path}")
end

# Get current version from first target's first configuration
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
    abort("Error: MARKETING_VERSION not found in any target's settings")
  end

  # Check if all versions match
  all_versions = versions.values.flatten.uniq
  if all_versions.size > 1
    puts "❌ Version mismatch detected:"
    versions.each do |target, target_versions|
      puts "  #{target}: #{target_versions.uniq.join(', ')}"
    end
    abort("Error: All targets must have the same version number")
  end

  # Return the common version
  all_versions.first
end

# print the version
puts get_version(project_path) 