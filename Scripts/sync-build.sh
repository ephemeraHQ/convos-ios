#!/usr/bin/env ruby
require 'xcodeproj'

# setup paths for the project
repo_root = Dir.pwd
project_path = File.expand_path('Convos.xcodeproj', repo_root)

# ensure project exists
unless File.exist?(project_path)
  abort("Error: Xcode project not found at #{project_path}")
end

# Update Xcode project build number
def increment_build_number(project_path)
  project = Xcodeproj::Project.open(project_path)
  project.targets.each do |target|
    # Skip targets that don't have CURRENT_PROJECT_VERSION
    next unless target.build_configurations.any? { |config| config.build_settings.key?('CURRENT_PROJECT_VERSION') }
    
    puts "\nProcessing target: #{target.name}"
    target.build_configurations.each do |config|
      if config.build_settings.key?('CURRENT_PROJECT_VERSION')
        current_build = config.build_settings['CURRENT_PROJECT_VERSION'].to_i
        new_build = current_build + 1
        config.build_settings['CURRENT_PROJECT_VERSION'] = new_build.to_s
        puts "  Incremented configuration '#{config.name}' build number from #{current_build} to #{new_build}"
      end
    end
  end
  project.save
  puts "\n✅ Successfully updated all targets in project at #{project_path}"
end

# increment the build number
increment_build_number(project_path)

puts "🏁 Finished build number increment" 