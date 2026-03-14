require 'xcodeproj'
project_path = 'VideoApp.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first
group = project.main_group.find_subpath('VideoApp', true)
file_ref = group.new_file('GoogleService-Info.plist')
target.add_file_references([file_ref])
project.save
