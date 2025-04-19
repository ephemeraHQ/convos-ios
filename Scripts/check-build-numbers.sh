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

# Check build numbers across all targets
def check_build_numbers(project_path)
  project = Xcodeproj::Project.open(project_path)
  
  # Get build numbers from all targets
  build_numbers = {}
  project.targets.each do |target|
    target.build_configurations.each do |config|
      if config.build_settings.key?('CURRENT_PROJECT_VERSION')
        build_number = config.build_settings['CURRENT_PROJECT_VERSION']
        build_numbers[target.name] ||= []
        build_numbers[target.name] << build_number
      end
    end
  end

  if build_numbers.empty?
    abort("Error: CURRENT_PROJECT_VERSION not found in any target's settings")
  end

  # Check if all build numbers match
  all_build_numbers = build_numbers.values.flatten.uniq
  if all_build_numbers.size > 1
    puts "❌ Build number mismatch detected:"
    build_numbers.each do |target, target_build_numbers|
      puts "  #{target}: #{target_build_numbers.uniq.join(', ')}"
    end
    abort("Error: All targets must have the same build number")
  end

  puts "✅ All targets have matching build number: #{all_build_numbers.first}"
end

# run the check
check_build_numbers(project_path) 