#!/usr/bin/env ruby
# Keep retired upstream integrations out of the two iOS shipping targets.
require 'xcodeproj'
require 'rexml/document'

root = File.expand_path('../..', __dir__)
project = Xcodeproj::Project.open(File.join(root, 'VLC.xcodeproj'))
retired_roots = %w[Network Cloud OnAir Podcasts Donation Onboarding].map { |name| "Sources/#{name}/" }
retired_roots += ['Sources/WiFi Sharing/', 'Resources/web/']
retained_files = %w[VLCArtworkCacher.m VLCDocumentPickerController.m]
retired_files = %w[CarPlayPodcastsController.swift VLCCarPlayOnAirController.m CPListTemplate+NetworkStreams.m
                   RadioStationEntity.swift PlayRadioStationIntent.swift VideoEntities.swift VideoIntents.swift
                   Reachability.m VLCActivityManager.m]
errors = []

%w[VLC-iOS VLC-iOS-no-watch].each do |name|
  target = project.targets.find { |item| item.name == name }
  abort "Missing target #{name}" unless target

  [target.source_build_phase, target.resources_build_phase].each do |phase|
    phase.files.each do |file|
      next unless file.file_ref
      path = file.file_ref.real_path.to_s.delete_prefix(root + '/')
      retired = retired_roots.any? { |prefix| path.start_with?(prefix) } && !retained_files.include?(File.basename(path))
      errors << "#{name} still ships #{path}" if retired || retired_files.include?(File.basename(path))
    end
  end

  target.frameworks_build_phase.files.each do |file|
    product = file.product_ref&.product_name
    errors << "#{name} still links #{product}" if %w[PCloudSDKSwift CocoaHTTPServer].include?(product)
  end
end

info = REXML::Document.new(File.read(File.join(root, 'Resources/iOS/Info.plist')))
schemes = REXML::XPath.match(info, '/plist/dict/key[text()="CFBundleURLTypes"]/following-sibling::array[1]//string')
errors << 'Legacy custom URL schemes are registered' unless schemes.empty?

abort errors.join("\n") unless errors.empty?
puts 'Both iOS targets exclude retired VLC integrations, SDKs and URL schemes.'
