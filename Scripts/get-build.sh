#!/usr/bin/env ruby
require 'xcodeproj'

# setup paths for the project
repo_root = Dir.pwd
project_path = File.expand_path('Convos/Convos.xcodeproj', repo_root)

# ensure project exists
unless File.exist?(project_path)
  abort("Error: Xcode project not found at #{project_path}")
end

# Get current build number
def get_build_number(project_path)
  project = Xcodeproj::Project.open(project_path)
  # Get build number from the first target's first configuration
  target = project.targets.first
  config = target.build_configurations.first
  if config.build_settings.key?('CURRENT_PROJECT_VERSION')
    config.build_settings['CURRENT_PROJECT_VERSION']
  else
    abort("Error: CURRENT_PROJECT_VERSION not found in project settings")
  end
end

# print the build number
puts get_build_number(project_path) 