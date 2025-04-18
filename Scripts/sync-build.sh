#!/usr/bin/env ruby
require 'xcodeproj'

# setup paths for the project
repo_root = Dir.pwd
project_path = File.expand_path('Convos/Convos.xcodeproj', repo_root)

# ensure project exists
unless File.exist?(project_path)
  abort("Error: Xcode project not found at #{project_path}")
end

# Update Xcode project build number
def increment_build_number(project_path)
  project = Xcodeproj::Project.open(project_path)
  project.targets.each do |target|
    target.build_configurations.each do |config|
      if config.build_settings.key?('CURRENT_PROJECT_VERSION')
        current_build = config.build_settings['CURRENT_PROJECT_VERSION'].to_i
        new_build = current_build + 1
        config.build_settings['CURRENT_PROJECT_VERSION'] = new_build.to_s
        puts "Incremented target '#{target.name}' - configuration '#{config.name}' build number from #{current_build} to #{new_build}"
      end
    end
  end
  project.save
  puts "✅ Successfully updated project at #{project_path}"
end

# increment the build number
increment_build_number(project_path)

puts "🏁 Finished build number increment" 