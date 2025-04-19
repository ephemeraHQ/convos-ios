#!/usr/bin/env ruby
require 'xcodeproj'

# Get version from command line argument
version = ARGV[0]
if version.nil? || version.strip.empty?
  abort("Error: version argument is required")
end

# setup paths for the project
repo_root = Dir.pwd
project_path = File.expand_path('Convos.xcodeproj', repo_root)

# ensure project exists
unless File.exist?(project_path)
  abort("Error: Xcode project not found at #{project_path}")
end

puts "Updating version to #{version} and resetting build number to 1"

# Update Xcode project
def update_project(project_path, version)
  project = Xcodeproj::Project.open(project_path)
  project.targets.each do |target|
    target.build_configurations.each do |config|
      # Update version
      if config.build_settings.key?('MARKETING_VERSION')
        config.build_settings['MARKETING_VERSION'] = version
        puts "Updated target '#{target.name}' - configuration '#{config.name}' version to #{version}"
      end
      
      # Reset build number
      if config.build_settings.key?('CURRENT_PROJECT_VERSION')
        config.build_settings['CURRENT_PROJECT_VERSION'] = '1'
        puts "Reset target '#{target.name}' - configuration '#{config.name}' build number to 1"
      end
    end
  end
  project.save
  puts "✅ Successfully updated project at #{project_path}"
end

# update the project
update_project(project_path, version)

puts "🏁 Finished version update"