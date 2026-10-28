#!/usr/bin/env ruby
# Copyright (c) 2026 Sandalbar Enterprises, Inc. See COPYING.
require 'xcodeproj'
require 'json'

root = File.expand_path('../..', __dir__)
artifact = File.join(__dir__, 'Artifacts/VLCKit.xcframework')
abort 'Build the native artifact with Buildsystem/RNNoise/build.sh first.' unless File.directory?(artifact)
project = Xcodeproj::Project.open(File.join(root, 'VLC.xcodeproj'))
if project.root_object.package_references.any? { |ref| ref.isa == 'XCLocalSwiftPackageReference' && ref.relative_path == 'Buildsystem/RNNoise' }
  puts 'The local RNNoise artifact is already activated.'
  exit
end
remote = project.root_object.package_references.find do |ref|
  ref.isa == 'XCRemoteSwiftPackageReference' && ref.repositoryURL == 'https://code.videolan.org/videolan/VLCKit.git'
end
abort 'The project no longer uses the expected upstream VLCKit dependency.' unless remote
local = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
local.relative_path = 'Buildsystem/RNNoise'
project.root_object.package_references << local
project.objects.grep(Xcodeproj::Project::Object::XCSwiftPackageProductDependency).each do |product|
  product.package = local if product.package == remote
end
remote.remove_from_project
project.save
lock = File.join(root, 'VLC.xcworkspace/xcshareddata/swiftpm/Package.resolved')
pins = JSON.parse(File.read(lock))
pins['pins'].reject! { |pin| pin['identity'] == 'vlckit' }
File.write(lock, JSON.pretty_generate(pins, space_before: ' ') + "\n")
puts 'Activated the local RNNoise-enabled VLCKit artifact.'
