#!/usr/bin/env ruby
require 'xcodeproj'

# setup paths for the project
repo_root = Dir.pwd
project_path = File.expand_path('Convos.xcodeproj', repo_root)

# ensure project exists
unless File.exist?(project_path)
  abort("Error: Xcode project not found at #{project_path}")
end

# Get current build numbers for all targets
def get_build_numbers(project_path)
  project = Xcodeproj::Project.open(project_path)
  build_numbers = {}
  
  project.targets.each do |target|
    # Skip targets that don't have CURRENT_PROJECT_VERSION
    next unless target.build_configurations.any? { |config| config.build_settings.key?('CURRENT_PROJECT_VERSION') }
    
    target.build_configurations.each do |config|
      if config.build_settings.key?('CURRENT_PROJECT_VERSION')
        build_numbers[target.name] ||= {}
        build_numbers[target.name][config.name] = config.build_settings['CURRENT_PROJECT_VERSION']
      end
    end
  end
  
  if build_numbers.empty?
    abort("Error: No targets with CURRENT_PROJECT_VERSION found in project settings")
  end
  
  build_numbers
end

# print the build numbers
build_numbers = get_build_numbers(project_path)
build_numbers.each do |target, configs|
  puts "\nTarget: #{target}"
  configs.each do |config, build|
    puts "  #{config}: #{build}"
  end
end 