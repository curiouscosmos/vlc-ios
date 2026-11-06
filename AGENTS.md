# Rajneesh Discourse iOS — Agent Guide

Contract for any agent (human or AI) working in this repository. Update it in the same commit as any change to
behaviour, commands, architecture or known gaps. History lives in git; keep this file under 300 lines. Detailed contracts live in `Buildsystem/AgentReference.md`; update them with related changes.

## 1. Mission

Rajneesh Discourse is a music-first fork of VLC for iOS distributed by Sandalbar Enterprises, Inc. It preserves
VLCKit/libvlc playback, the local library, playlists, background audio and lock-screen controls, and adds a curated
catalogue of Osho discourse audio from a REST backend plus search, downloads, likes, listening history and a second
simultaneous channel (the Audio Mixer). Dark-first, no video surface, anonymous device-UUID identity, GPLv2+/GPLv3.
Tagline *"Your music-first local media player"*; website <https://rajneeshdiscourse.com>. Android reference
<https://github.com/curiouscosmos/mix-wave-android> (local `/Users/damanmehta/AI/vlc-android`, `master`); iOS is a
native reimplementation of its behaviour, not a port.

## 2. Non-negotiables

1. **Fork, not rewrite.** Preserve VLCKit, `VLCPlaybackService`, the library, playlists, background audio and the build
   system. Never add a second architecture beside the existing one.
2. **Keep licensing.** Preserve copyright headers, `COPYING` and third-party notices.
3. **Minimal diffs.** Reuse existing classes and patterns; keep fork code in `Sources/Discourse/` and every upstream
   edit small and listed in §11.
4. **No secrets.** `x-api-key` comes from `.env*`/`Secrets.xcconfig`/environment and the build fails without it. Never
   commit keys, `.env*` or `Secrets.xcconfig`.
5. **Dark default**, light must work. **Music-first**: exactly five tabs (Home, Discourses, Search, Playlists, Mixer);
   no Browse/Videos surface.
6. **Never wire the backend `/seed` route.**
7. **This file is a contract**: update it with behaviour, commands, architecture and gaps.
8. **Small coherent commits** prefixed by area, describing why; commit **and push** finished work to `origin`
   (`https://github.com/curiouscosmos/vlc-ios.git`) unless told otherwise.
9. Spec/iOS conflicts: preserve observable behaviour, follow iOS conventions, and record the deviation in §10.

## 3. Build, run, test

### 3.1 Prerequisites

Xcode 26.4.1 (17E202; CI tag `macos-xcode26`), CocoaPods 1.16.2, Swift 5.0 language mode (mixed Swift + ObjC), Ruby
`xcodeproj` 1.27.0. CocoaPods needs `export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8` or it fails with a Unicode error.

### 3.2 First-time setup

```bash
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
Buildsystem/RNNoise/build.sh   # local VLCKit artifact (long first build)
pod install                    # Pods/ + VLC.xcworkspace
```

SPM dependencies resolve on first build (pinned in `VLC.xcworkspace/xcshareddata/swiftpm/Package.resolved`).

### 3.3 Build the app

Workspace `VLC.xcworkspace`. Use the **`VLC-iOS-no-watch`** scheme: plain `VLC-iOS` embeds a watch app and needs a
matching watchOS runtime. Products are `VLC-iOS-no-watch.app` and `VLC for iOS.app`; both use bundle id
`com.oshodiscourse` — install the one you just built.

```bash
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
xcodebuild -workspace VLC.xcworkspace -scheme VLC-iOS-no-watch -configuration Debug \
  -destination 'generic/platform=iOS Simulator' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO build

# Concrete simulator: pin OS= or use a UDID ("name=iPhone 16" is ambiguous)
xcodebuild ... -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' build
xcodebuild ... -destination 'platform=iOS Simulator,id=<UDID>' build
xcrun simctl boot "iPhone 16"
xcrun simctl install booted "<DerivedData>/Build/Products/Debug-iphonesimulator/VLC-iOS-no-watch.app"
xcrun simctl launch --console booted com.oshodiscourse
```

Shared schemes: `VLC-iOS`, `VLC-iOS-no-watch`, `VLC-iOS-Tests`, `VLC-iOS-UITests`, `VLC-iOS-Screenshots`,
`VLC-ShareExtension`, `VLC-tvOS`, `VLC-visionOS`, `VLC-watchOS`; only the iOS app targets matter.

Identifiers: app `com.oshodiscourse`, widget `.widget`, share extension `.shareextension`, watch `.watchos`, app group
`group.com.oshodiscourse`. Podcast URL registration supports `feed`, `feeds`, `itpc` (`pcast` fails App Store
validation). `project.pbxproj` uses classic `PBXGroup`s; register files and target membership with
`ruby Buildsystem/scripts/add_to_xcodeproj.rb "Sources/Discourse" "Foo.swift" "VLC-iOS"` (or `--target VLC-iOSTests`).
Never hand-edit pbxproj UUIDs; rebuild after every `pod` command.

### 3.4 API key (no secrets)

`Buildsystem/scripts/check_api_key.sh` is the *Generate Discourse API Secrets* run-script phase on `VLC-iOS` and
`VLC-iOS-no-watch`: it fails the build without a key and otherwise writes `DiscourseSecrets.h` into
`$(SHARED_DERIVED_FILE_DIR)` (never the source tree). The bridging header imports it, so `DiscourseAPIClient` sees
`RD_API_KEY` / `RD_API_BASE_URL` (default `https://oshoapi-0i8tq.bunny.run/`, override `OSHO_API_URL`). Supply the key
through any gitignored source (checked in order): `API_KEY=…` in `.env.production`; `OSHO_API_KEY=…` in `.env`;
`API_KEY = …` in `Secrets.xcconfig`; or `export OSHO_API_KEY=…`. `.gitignore` must list all of them.

### 3.5 Tests

XCTest only, outside `Sources/` under `Buildsystem/Testing/`. The test schemes build the watch-embedded `VLC-iOS` host,
so install a matching watchOS runtime (`xcodebuild -downloadPlatform watchOS`; 26.4 is installed here).
`VLC-iOS-no-watch` has no test target.

```bash
xcodebuild -workspace VLC.xcworkspace -scheme VLC-iOS-Tests -configuration Debug \
  -destination 'platform=iOS Simulator,id=<UDID>' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO test
xcodebuild ... -scheme VLC-iOS-UITests -destination ... test
```

Unit suites (`Buildsystem/Testing/Unit/`): API, stores, formatting, playback, playback progress, search, home,
downloads, mixer, clips, captions, deep links, RNNoise (ObjC), launch screen. UI (`Buildsystem/Testing/UI/VLCTestMenu.swift`): one test
per tab, catalogue → detail, search, Home, like round trip, download, mixer picker, playback-history setting.
Screenshots use `Buildsystem/Testing/Screenshots/` (`VLC_SCREENSHOTS_OUTPUT`).

### 3.6 Lint & CI

`Buildsystem/swiftlint.yml` (small explicit rule set; one space around `=`); `swiftlint` is installed by CI, not
locally. CI is `Buildsystem/gitlab-ci.yml` (lint, build; **no test stage**); when the local RNNoise package is active
it runs `Buildsystem/RNNoise/build.sh` before resolving packages.

### 3.7 RNNoise

Read `Buildsystem/RNNoise/README.md`. `build.sh` builds pinned patched VLCKit/libvlc; `ruby
Buildsystem/RNNoise/activate.rb` switches the project to the local binary package. A clean checkout must build that
ignored artifact; upstream VLCKit still builds with noise reduction unavailable. Never patch Xcode's dependency
checkouts.

### 3.8 Universal Links

`https://rajneeshdiscourse.com/discourses/{id}` and `.../tracks/{audioId}` open the app. Entitlements declare
`applinks:rajneeshdiscourse.com`; `DiscourseDeepLink` parses and `TabBarCoordinator.handleDiscourseDeepLink(_:)`
routes; `VLCAppDelegate`/`VLCAppCoordinator` queue the link until the passcode gate releases the tab bar. Track links
pass `highlightedAudioID`, which scrolls the table once. The site must serve
`/.well-known/apple-app-site-association` (`application/json`, no redirects); the deployable file is in
`Buildsystem/DeepLinks/`. Without it, links open Safari.

## 4. Architecture map

Before changing navigation, theming, playback, API/stores, UI, downloads or the mixer, read the relevant §4 subsection in [AgentReference.md](Buildsystem/AgentReference.md#4-architecture-map). It names ownership boundaries and integration paths.

- Preserve the existing VLC playback/library architecture; the mixer alone owns a second player.
- Use `DiscourseColors` for fork screens and existing notifications/stores for state changes.
- Attribute discourse media with `identity(of:)`; paused restoration must never auto-start playback or the mixer.

## 5. Repository conventions

- Match surrounding style; Swift 5 language mode with heavy ObjC interop; `@objc(VLCWhatever)` for public ObjC-visible
  Swift; `final class` for new leaf types; no force-unwraps; import only what is needed.
- One bridging header exposes VLCKit, VLCMediaLibraryKit, XKKeychain, `DiscourseSecrets.h` and
  `VLCNetworkImageView.h`; honour `NS_ASSUME_NONNULL_*`.
- Upstream types keep their names; fork types use the `Discourse` prefix.
- Every user-facing string via `NSLocalizedString` and added to `en.lproj`; every control has an
  `accessibilityLabel`; support Dynamic Type.
- New images go in `Resources/iOS/Images.xcassets`; theme colours are code, not colour sets. Do not add a third-party
  dependency — the fork uses URLSession, Codable, UserDefaults/Keychain and existing VLC types.
- One coherent change per commit, prefixed by area and describing why; never commit artefacts, `Pods/`,
  `DerivedData`, `.env*` or secrets.

## 6. Product requirements

Before changing observable behaviour, read the corresponding §6 contract in [AgentReference.md](Buildsystem/AgentReference.md#6-product-requirements), including exact copy, defaults and thresholds.

- Five tabs: Home, Discourses, Search, Playlists, Mixer. Home drops empty sections; history-off hides track history.
- Qualify history/stats after 60 s of actual playback; stats dedupe is 24 h; likes refresh is seven days.
- Successful like responses preserve the tap’s count direction; optimistic likes roll back on failure; confirmed counts survive stale catalogue payloads for the session.
- Completing a download switches an actively streaming track to its verified local file at the current position; paused tracks never auto-start.
- Downloads play locally only when verified; destructive remove-all and mixer clear-all actions confirm.
- Disabled Mixer panel labels are “Mixer” and “Background music”. Pausing the mixer with its play/pause button turns it off (the persisted switch clears); it stays off across later tracks until the user presses play again, and it never auto-resumes.
- Playlists shows its logo/empty-state text only when ordinary playlists and presentable favourite collections are both empty.
- Playlist list cards use 112 × 88 pt aspect-fill artwork, at least 112 pt height and a track count (details in reference §4.6).
- Clip Share supports discourse tracks: draggable range defaults to current time + 10 min, minimum 1 s, no maximum beyond the track. Entering the editor pauses playback; Bracket drags, endpoint +/− controls and caption selections immediately move the preview playhead: start edits use the start time; end edits use max(start, end − 10 s). Edits never start paused playback; the next Play starts at that preview position and stops at the end. Preview uses a one-shot absolute-time seek after resume; position ticks never re-arm it. Verified local discourse files use the bundled avformat demuxer for accurate seeking. Cut opens Save Clip; Share Link to Track (subtitle “Share clip link with anyone”) opens the system share sheet with the track title and `/discourses/{discourseID}/tracks/{audioID}?start={seconds}&end={seconds}`; Clip requires a verified download; missing sources show a dismissible download prompt. The action row has the track-card download control (green when complete); Add to Playlist precedes Discourse in the top bar. Download Clip exports processed 48 kHz stereo AAC/M4A; Export Video picks one photo/video and exports H.264/MP4. Enabled noise cancellation and mixer settings are captured at export start; mixer audio starts at zero, with its volume/loop setting. Export CC defaults off per drawer and saves a clip-timed UTF-8 SRT beside the media through Files. Exports cancel on background.
- Clip panel has separate one-second start/end adjustment buttons, disabled at range limits; full-track edge labels, a floating playhead time, and Selected duration beside Cut. Base height is 168 pt with Dynamic Type scaling; transport alignment stays fixed, and portrait artwork shrinks as needed to keep the bottom controls visible.
- Captions: `discourse_audio.has_cc` plus a valid `cc_path` enables CC in the expanded player. CC replaces portrait artwork and title/artist/discourse metadata with the full scrolling SRT transcript, highlighting the current phrase (not estimated words). Opening Clip shows available captions; start is initially active. Tap/drag a bracket or use its adjustment buttons to activate it; phrase taps keep setting that bracket to phrase start/end respectively, clamped by existing one-second range rules. Playback never starts from a caption tap.
- Expanded-player hearts match the action icons at zero likes; positive counts keep the compact heart.
- Track cards show the title once; subtitles put duration first and omit a matching discourse name.
- Detail track rows keep the duration, download and like controls at their intrinsic width; long titles wrap to a second line instead of squeezing the icons.
- Player scrub-bar seeks capture the chosen time when the gesture ends, hold the display until the player reports it, and use absolute timestamps for audio, so streaming position updates cannot snap a 20-minute seek back to the pre-seek time.
- Dark is the default; light, Dynamic Type, accessibility and localisation must work.

## 7. Local persistence contract

Before changing persisted state, read the key/type/owner table in [AgentReference.md §7](Buildsystem/AgentReference.md#7-local-persistence-contract). Preserve `osho_api_*` / `audio_mixer_*` names, decode corrupt JSON defensively and serialise writes. Keep secrets and UUIDs out of logs.

## 8. Testing and verification

Automated: `DiscourseAPITests`, `DiscourseStoresTests`, `DiscourseFormattingTests`, `DiscoursePlaybackTests`, `DiscoursePlaybackProgressTests`, `DiscourseSearchTests`, `DiscourseHomeTests`, `DiscourseDownloadTests`, `DiscourseMixerTests`, `DiscourseDeepLinkTests`, `DiscourseClipTests`, `DiscourseCaptionTests`, `DiscourseLaunchScreenTests`, `DiscourseNoiseReductionTests` (ObjC, needs RNNoise), plus upstream URL/preference tests — currently **206 unit tests** and **19 UI tests** (§3.5).

Manual: clean build; local playback/playlists/background/lock screen; five tabs and branding; catalogue paging/filters/refresh; detail queue continuation; Home sections/states; like persistence and rollback; 60 s qualification and 24 h stats dedupe; downloads (progress/cancel/remove/offline); mixer add/select/reorder/remove/clear/follow/volume/relaunch; VoiceOver, Dynamic Type, light theme; offline, interruption, route change and media-services reset on a device. UI tests cover navigation, catalogue → detail, search, Home, the like round trip, the download round trip (skips on a slow CDN), the mixer picker, playback history, payload-less favourites, and clip preview progress and end stopping, and the clip editor/save drawer link sharing, video-picker cancellation and processed-audio Files saving.

## 9. Current status

Playback performance: five-second checkpoints reuse queue metadata and write on the snapshot queue; lifecycle saves drain writes synchronously. Queue identity records persist in batches, and identity/progress indexes stay in memory under their existing serial owners. Download progress is coalesced and targets affected controls; Home reuses local history until the library changes and skips unchanged sections; detail cache reads/sorting run off-main and unchanged track lists skip registration/rendering.

Phases 1–15 are implemented, in delivery order: docs, branding, API/cache/identity, stores, five-tab shell, catalogue, detail, search, Home, playback/resume/stats/history, likes and favourite collections, downloads, mixer, playlist styling, accessibility/localisation. Recent work: processed M4A exports, photo/video MP4 exports and optional clip-timed SRT sidecars; phrase-timed SRT captions in the expanded player and caption-driven active clip brackets; on-device Clip Share with range preview and Files export; player artwork restoration now recovers the audio object's `discourse_thumbnail_url` when older snapshots lack it, refreshes service metadata, and prefers it over a local-library thumbnail; paused queue restoration; alphabetically grouped catalogue with compact letter badges (no side index; most-liked keeps its ranking), Google Drive/OneDrive/ADAL removal (no `UIWebView`), removal of AlarmKit/Face ID/photo saving/iCloud Documents, artwork swipes, track sharing, stale-while-revalidate, hiding payload-less favourite rows, a mixer pause that stays off across track changes until the user restarts it, and streaming scrub-bar seeks that keep the user's target instead of snapping back to the pre-seek time. The mixer is never built before playback is stable.

Open: caption synchronization/VoiceOver and caption clip selection need physical-device acceptance; captions are opportunistically cached, not bundled with audio downloads. Clip Share iCloud/HDR/audio-sync and Files physical-device acceptance is pending; automated clip/caption suites pass 23 tests on the simulator and 22 on iPhone 14 Pro (iOS 26.6.1), excluding the existing panel-bounds assertion that fails on that device; `POST /favourites/resolve` is implemented in `api/edge.ts` but not deployed (no command/credentials here); the AASA is unpublished; RNNoise device acceptance is pending; tests need a watchOS runtime; physical-device audio and passcode UI are manual checks.

## 10. Known gaps and intentional deviations

Before implementing a feature or resolving a spec/iOS conflict, check [AgentReference.md §10](Buildsystem/AgentReference.md#10-known-gaps-and-intentional-deviations). Record new gaps there; preserve observable behaviour and follow iOS conventions.

## 11. Upstream sync policy

Before an upstream sync or editing upstream files, read [AgentReference.md §11](Buildsystem/AgentReference.md#11-upstream-sync-policy); maintain its touch-point inventory. Preserve fork behaviour during conflicts, run `pod install`, rebuild and repeat §8 verification. Update status and deviations in the same commit.
