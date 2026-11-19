#!/usr/bin/env ruby
# Keep retired upstream integrations out of the two iOS shipping targets.
require 'xcodeproj'
require 'rexml/document'

root = File.expand_path('../..', __dir__)
project = Xcodeproj::Project.open(File.join(root, 'VLC.xcodeproj'))
retired_roots = %w[Network Cloud OnAir Podcasts Donation Onboarding].map { |name| "Sources/#{name}/" }
retired_roots += ['Sources/WiFi Sharing/', 'Sources/Playback/Subtitles Downloading/', 'Resources/web/']
retained_files = %w[VLCArtworkCacher.m VLCDocumentPickerController.m]
retired_files = %w[CarPlayPodcastsController.swift VLCCarPlayOnAirController.m CPListTemplate+NetworkStreams.m
                   RadioStationEntity.swift PlayRadioStationIntent.swift VideoEntities.swift VideoIntents.swift
                   Reachability.m VLCActivityManager.m VideoViewController.swift VideoPreviewController.swift
                   VideoPlayerViewController.swift VideoPlayerViewController+ControlsDelegate.swift
                   VideoPlayerControls.swift VideoPlayerControls.xib VideoFiltersControlsView.swift PictureInPictureMediaController.swift
                   PlaybackServiceAdjustFilter.swift TrackSelectorView.swift TrackSelectorCell.swift PlaybackDelayView.swift
                   AspectRatio.swift UIScreen+Brightness.swift VideoPlayback.xcassets
                   DeviceMotion.swift VLCNonInteractiveWindowSceneDelegate.m VLCExternalDisplayController.m]
errors = []

%w[VLC-iOS VLC-iOS-no-watch].each do |name|
  target = project.targets.find { |item| item.name == name }
  abort "Missing target #{name}" unless target

  engine = target.frameworks_build_phase.files.filter_map(&:product_ref).find { |product| product.product_name == 'VLCKit' }&.package
  unless engine&.isa == 'XCLocalSwiftPackageReference' && engine.relative_path == 'Buildsystem/AudioEngine'
    errors << "#{name} must link the local audio engine"
  end

  [target.source_build_phase, target.resources_build_phase].each do |phase|
    phase.files.each do |file|
      next unless file.file_ref
      path = file.file_ref.real_path.to_s.delete_prefix(root + '/')
      retired = retired_roots.any? { |prefix| path.start_with?(prefix) } && !retained_files.include?(File.basename(path))
      errors << "#{name} still ships #{path}" if retired || retired_files.include?(File.basename(path))
    end
  end

  target.frameworks_build_phase.files.each do |file|
    product = file.product_ref&.product_name || file.file_ref&.display_name
    errors << "#{name} still links #{product}" if %w[PCloudSDKSwift CocoaHTTPServer VideoToolbox.framework].include?(product)
  end
end

info = REXML::Document.new(File.read(File.join(root, 'Resources/iOS/Info.plist')))
schemes = REXML::XPath.match(info, '/plist/dict/key[text()="CFBundleURLTypes"]/following-sibling::array[1]//string')
errors << 'Legacy custom URL schemes are registered' unless schemes.empty?
scenes = REXML::XPath.match(info, '//key[starts-with(text(), "UIWindowSceneSessionRoleExternalDisplay")]')
errors << 'External video-display scenes are registered' unless scenes.empty?
siri = REXML::XPath.match(info, '//string[text()="INMediaCategoryVideo"]')
errors << 'Siri advertises video playback' unless siri.empty?
movie_types = REXML::XPath.match(info, '//string[text()="public.movie" or text()="public.video"]')
errors << 'The iOS app advertises movie types' unless movie_types.empty?
%w[Root Root.inApp].each do |name|
  settings = REXML::Document.new(File.read(File.join(root, "Resources/iOS/Settings.bundle/#{name}.plist")))
  retired_keys = /video|subtitle|deinterlac|hardware.?decod|skip.?loop.?filter|brightness|noise.?reduction/i
  REXML::XPath.match(settings, '//key[text()="Key"]/following-sibling::string[1]').each do |key|
    errors << "#{name} exposes retired preference #{key.text}" if retired_keys.match?(key.text.to_s)
  end
end
share = REXML::Document.new(File.read(File.join(root, 'Sources/ShareExtension/Info.plist')))
activation = REXML::XPath.first(share, '//key[text()="NSExtensionActivationRule"]/following-sibling::*[1]')
unless activation&.name == 'string' &&
       activation.text.include?('ANY $attachment.registeredTypeIdentifiers UTI-CONFORMS-TO "public.audio"') &&
       %w[movie video].all? { |type| activation.text.include?("NONE $attachment.registeredTypeIdentifiers UTI-CONFORMS-TO \"public.#{type}\"") } &&
       activation.text.include?(').@count == $item.attachments.@count')
  errors << 'The share extension must require an audio-only selection'
end

abort errors.join("\n") unless errors.empty?
puts 'Both iOS targets exclude retired integrations, video controls, retired settings, SDKs and URL schemes.'
