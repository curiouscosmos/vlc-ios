# Rajneesh Discourse iOS — Agent Guide

This document is the contract for any agent (human or AI) working in this repository.
It is a living document: **update it in the same commit as any change to behaviour,
commands, architecture, or known gaps.** Sections 9, 10 and 11 in particular must
never go stale.

---

## 1. Mission

Rajneesh Discourse is a **music-first fork of VLC for iOS** distributed by Sandalbar
Enterprises, Inc. It preserves VLC's playback engine (VLCKit/libvlc), local media
library, playlists, background audio and lock-screen controls, and adds a curated
catalogue of **Osho discourse audio** served by a REST backend, plus search,
downloads, likes, listening history and a second simultaneous audio channel (the
**Audio Mixer**). The app is dark-theme-first, has no video product surface, and
talks to the backend anonymously with a device-generated UUID. It remains free
software under GPLv2+/GPLv3.

- Product name: **Rajneesh Discourse**
- Tagline: *"Your music-first local media player"*
- Website / help: <https://rajneeshdiscourse.com>
- Android reference implementation: <https://github.com/curiouscosmos/mix-wave-android>
  (local checkout for comparison: `/Users/damanmehta/AI/vlc-android`, branch `master`).
  This iOS app is a **native reimplementation** of that behaviour, not a port.

---

## 2. Read this first / non-negotiables

1. **This is a fork, not a rewrite.** Preserve VLCKit, the playback pipeline, the
   media library, local playback, playlists, background audio, lock-screen controls
   and the existing build system. Add the discourse layer *around* the existing
   architecture. Never introduce a second architecture beside the existing one.
2. **Never remove upstream licensing or attribution.** Keep copyright headers,
   `COPYING` and third-party notices. Any distributed binary remains
   source-available under the same licence (GPLv2+/GPLv3).
3. **Minimal diffs.** Reuse existing patterns (view controllers, playback service,
   media models, persistence). Prefer extending an existing class over adding a
   parallel one.
4. **No secrets in the repository.** The API requires `x-api-key`. It is read from
   the environment / a gitignored `.env` / a gitignored `Secrets.xcconfig`. The
   build must **fail clearly** if it is missing. Never commit the key. See §3.4.
5. **Dark theme is the default.** Light mode must work; first launch is dark.
6. **Music-first navigation.** Exactly five bottom destinations: Home, Discourses,
   Search, Playlists, Audio Mixer. No Browse tab, no Videos tab, no video browsing
   screen. The engine may still play a video if the user opens a file, but video is
   not a product surface.
7. **Do not integrate the backend `/seed` route.**
8. **Update this file whenever behaviour, commands, architecture, or known gaps
   change.**
9. **Small coherent commits** with descriptive messages. Never mix unrelated
   refactors into feature commits.
10. **When the spec and the iOS codebase conflict:** preserve observable behaviour,
    adapt to iOS conventions, and record the deviation in §10.

---

## 3. Build, run, test

### 3.1 Prerequisites

| Tool | Version used here | Notes |
|---|---|---|
| Xcode | 26.4.1 (build 17E202) | CI runner tag is `macos-xcode26` |
| CocoaPods | 1.16.2 (`pod`) | needs a UTF-8 locale, see below |
| Swift | 5.0 language mode (`SWIFT_VERSION = 5.0`) | mixed Swift + Objective-C |
| Ruby / `xcodeproj` gem | 1.27.0 | used to register new files in the project |

**CocoaPods locale gotcha.** Running `pod` without a UTF-8 locale fails with
`Unicode Normalization not appropriate for ASCII-8BIT`. Always export the locale:

```bash
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
```

### 3.2 First-time setup

```bash
cd /Users/damanmehta/AI/vlc-ios
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
Buildsystem/RNNoise/build.sh # builds the local VLCKit artifact (long first build)
pod install            # installs Pods/ and rewrites VLC.xcworkspace
```

Swift Package Manager dependencies (VLCKit, VLCMediaLibraryKit, XKKeychain, …)
resolve automatically on first build; they are pinned in
`VLC.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

### 3.3 Build the app

Workspace: `VLC.xcworkspace`. Products:
`VLC-iOS-no-watch.app` (the day-to-day scheme), `VLC for iOS.app` (the
watch-embedded `VLC-iOS` scheme and the test hosts) and the share/widget
extensions. Both app products use bundle id `com.example.vlc-ios`; install the one
that belongs to the scheme you just built.

**Use the `VLC-iOS-no-watch` scheme.** The plain `VLC-iOS` scheme embeds an Apple
Watch app and therefore requires a matching watchOS simulator runtime to be
installed (`watchOS 26.4 must be installed in order to run the scheme`). The
`-no-watch` scheme builds the same iOS app without that requirement and is what
this fork uses. Verified working:

```bash
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
xcodebuild -workspace VLC.xcworkspace -scheme VLC-iOS-no-watch -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO build
```

To run on a specific simulator, replace the destination with a concrete device.
`name=iPhone 16` alone is **ambiguous** (multiple runtimes) and will fail
destination resolution — always pin `OS=` or use a UDID:

```bash
xcodebuild -workspace VLC.xcworkspace -scheme VLC-iOS-no-watch -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO build
```

Available shared schemes (`VLC.xcodeproj/xcshareddata/xcschemes/`):
`VLC-iOS`, `VLC-iOS-no-watch`, `VLC-iOS-Tests`, `VLC-iOS-UITests`,
`VLC-iOS-Screenshots`, `VLC-ShareExtension`, `VLC-tvOS`, `VLC-visionOS`,
`VLC-watchOS`. **Only the iOS app targets are relevant to this product.**

Simulator list: `xcrun simctl list devices available`.
Install + launch a built app:

```bash
xcrun simctl boot "iPhone 16"
xcrun simctl install booted "<DerivedData>/Build/Products/Debug-iphonesimulator/VLC-iOS-no-watch.app"
xcrun simctl launch --console booted com.example.vlc-ios
```

The product folder holds both `VLC-iOS-no-watch.app` and `VLC for iOS.app`; the
latter belongs to the watch scheme and is refreshed by test runs, so installing it
after a `-no-watch` build silently ships stale code. Check the timestamp and the
scheme before reporting a visual regression.

The iOS app bundle id is `com.oshodiscourse`. Its Media Library widget uses
`com.oshodiscourse.widget`, and the Share extension uses
`com.oshodiscourse.shareextension`; both identifiers use one suffix after the
app id for App Store validation. The Watch app uses
`com.oshodiscourse.watchos` and declares `com.oshodiscourse` as its companion
app. The shared app group is `group.com.oshodiscourse`. Other upstream targets
may still derive identifiers from `BUNDLE_IDENTIFIER_PREFIX` in
`Buildsystem/SharedConfig.xcconfig`. Podcast feed URL registration supports
`feed`, `feeds`, and `itpc`; `pcast` is omitted because App Store validation
rejects that scheme.

> **Note on `pod install` and `project.pbxproj`.** New source files are registered
> in `VLC.xcodeproj/project.pbxproj` (classic `PBXGroup`, *not* a synchronized
> folder). Use `Buildsystem/scripts/add_to_xcodeproj.rb` (see §5.6) so references,
> build phases and target membership stay consistent. CocoaPods preserves these
> references across `pod install`, but always re-run a build after a `pod` command.

### 3.4 API key / build configuration (no secrets)

The backend requires an `x-api-key` header on every request. The key never lives
in source control: a build phase generates a header with the values and Swift
reads them through the iOS bridging header.

- `RD_API_BASE_URL` — default `https://oshoapi-0i8tq.bunny.run/`, overridable
  with `OSHO_API_URL`.
- `RD_API_KEY` — **must** be supplied by the developer.

`Buildsystem/scripts/check_api_key.sh` is wired as the *Generate Discourse API
Secrets* "Run Script" phase on `VLC-iOS` and `VLC-iOS-no-watch`, ahead of
*Compile Sources*. It fails the build with an actionable message when the key is
missing and otherwise writes `DiscourseSecrets.h` into
`$(SHARED_DERIVED_FILE_DIR)` (never the source tree). The phase is marked
always-out-of-date so a rotated key is picked up on the next build.

The header reaches Swift through two project settings:

- `HEADER_SEARCH_PATHS` on `VLC-iOS`, `VLC-iOS-no-watch` and `VLC-iOSTests`
  includes `$(SHARED_DERIVED_FILE_DIR)` and `$(DERIVED_FILE_DIR)`;
- `Sources/Headers/VLC-iOS-Bridging-Header.h` imports `DiscourseSecrets.h`, so
  `DiscourseAPIClient` sees `RD_API_KEY` / `RD_API_BASE_URL` as Swift constants.

Building a clean checkout without a key stops at that phase — by design.

Ways to supply the key, in the order `check_api_key.sh` consults them (all
gitignored; copy `.env.example` to `.env.production`):

```bash
# Option A — .env.production at repo root (gitignored; project convention)
echo 'API_KEY=your-key-here' > .env.production

# Option B — .env at repo root (gitignored)
echo 'OSHO_API_KEY=your-key-here' > .env

# Option C — Secrets.xcconfig at repo root (gitignored)
echo 'API_KEY = your-key-here' > Secrets.xcconfig

# Option D — environment (any of API_KEY / OSHO_API_KEY)
export OSHO_API_KEY=your-key-here
```

Never commit `.env*`, `Secrets.xcconfig`, or any key. `.gitignore` must list them.

### 3.5 Tests

XCTest only (no Swift Testing). Test targets and sources live **outside**
`Sources/`, under `Buildsystem/Testing/`:

```bash
# Unit tests (VLC-iOSTests)
xcodebuild -workspace VLC.xcworkspace -scheme VLC-iOS-Tests \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO test

# UI tests (VLC-iOSUITests)
xcodebuild -workspace VLC.xcworkspace -scheme VLC-iOS-UITests \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO test
```

**Prerequisite.** The upstream `VLC-iOS-Tests`, `VLC-iOS-UITests` and
`VLC-iOS-Screenshots` schemes build the watch-embedded `VLC-iOS` app as their
test host, so they need a matching watchOS simulator runtime (watchOS 26.4 is
installed on this machine and the unit tests run green). On a machine without
it, install once:

```bash
xcodebuild -downloadPlatform watchOS
```

Without it these schemes fail with *"This scheme builds an embedded Apple Watch
app. watchOS X must be installed …"*. The `VLC-iOS-no-watch` scheme has no test
target, so tests run through `VLC-iOS-Tests`. Verified command:

```bash
xcodebuild -workspace VLC.xcworkspace -scheme VLC-iOS-Tests -configuration Debug \
  -destination 'platform=iOS Simulator,id=<UDID>' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO test
```

- Unit: `Buildsystem/Testing/Unit/` (`URLHandlerTests.swift`,
  `PreferenceSettingTests.swift`,
  `DiscourseAPITests.swift`, `DiscourseStoresTests.swift`,
  `DiscourseFormattingTests.swift`, `DiscoursePlaybackTests.swift`,
  `DiscourseSearchTests.swift`, `DiscourseHomeTests.swift`,
  `DiscoursePlaybackProgressTests.swift`, `DiscourseDownloadTests.swift`,
  `DiscourseMixerTests.swift`, `DiscourseDeepLinkTests.swift`,
  `DiscourseNoiseReductionTests.m`).
- UI: `Buildsystem/Testing/UI/` (`VLCTestMenu.swift` + helpers).
- Screenshots: `Buildsystem/Testing/Screenshots/Screenshot.swift` +
  `take-screenshots.sh` (env `VLC_SCREENSHOTS_OUTPUT`).
- New discourse tests go in `Buildsystem/Testing/Unit/` and must be registered in
  the `VLC-iOSTests` target (`add_to_xcodeproj.rb … --target VLC-iOSTests`).

> The `VLCTestMenu.swift` UI tests were rewritten in Phase 5 for the five-tab
> shell (one test per destination, catalogue navigation, About via the Settings
> menu). The Mixer test opens **Add audio file** and cancels the system document
> picker; it also asserts that the removed Local Library action is absent.

### 3.6 Lint & CI

- Lint config: `Buildsystem/swiftlint.yml` (small explicit rule set; whitespace
  around `=` is enforced). `swiftlint` is **not** installed locally by default;
  CI installs it.
- CI: `Buildsystem/gitlab-ci.yml` (GitLab). Stages: `lint`, `build`. **There is
  no test stage in CI** — run tests locally. The `before_script` runs
  `pod update`. When the local RNNoise dependency is activated, build jobs run
  `Buildsystem/RNNoise/build.sh` before Swift package resolution.

---

### 3.7 RNNoise native engine

For RNNoise builds or dependency updates, read `Buildsystem/RNNoise/README.md`.
`Buildsystem/RNNoise/build.sh` builds pinned, patched VLCKit/libvlc sources;
`ruby Buildsystem/RNNoise/activate.rb` switches the project to its local binary
package after the artifact exists. The project currently uses this local package;
a clean checkout must build the ignored artifact before resolving packages.
The app also supports upstream VLCKit with noise reduction unavailable. Never
patch Xcode's generated dependency checkouts.

### 3.8 Universal Links

The website links `https://rajneeshdiscourse.com/discourses/{id}` and
`.../tracks/{audioId}` open the app. The app-side pieces are:

- `com.apple.developer.associated-domains` = `applinks:rajneeshdiscourse.com`
  in all three iOS entitlements files;
- `DiscourseDeepLink` (`Sources/Discourse/DeepLink/`) parsing and
  `TabBarCoordinator.handleDiscourseDeepLink(_:)` routing;
- `VLCAppDelegate`/`VLCAppCoordinator` queue the link until the tab bar
  survives the passcode gate.

The website must publish
`https://rajneeshdiscourse.com/.well-known/apple-app-site-association`
(`Content-Type: application/json`, no `.json` suffix, no redirects). The
deployable file and the exact Team ID/bundle note live in
`Buildsystem/DeepLinks/`. Without it, iOS opens Safari.

## 4. Architecture map

This is VLC for iOS `4.0.0` (build 715), deployment target **iOS 15.0**, mixed
**Swift + Objective-C**, `main.m` → `VLCAppDelegate` → **UIKit scene delegate**.

### 4.1 App shell, navigation and theming

| Concern | File(s) |
|---|---|
| Entry point | `Sources/App/iOS/main.m` |
| App delegate (registeres ~90 `NSUserDefaults` defaults) | `Sources/App/iOS/VLCAppDelegate.{h,m}` |
| Scene delegate — **sets the root VC** (`VLCBottomTabBarController`) | `Sources/App/iOS/VLCAppSceneDelegate.{h,m}` |
| App coordinator (singleton; builds tabs, mini-player overlay, media library) | `Sources/App/VLCAppCoordinator.{h,m}` |
| Tab bar controller | `Sources/UI Elements/View Controller/BottomTabBarController.swift` |
| Tab construction / order / selection | `Sources/App/iOS/TabBarCoordinator.swift` |
| Theme model (semantic `ColorPalette`, hard-coded hex) | `Sources/UI Elements/PresentationTheme.swift` |
| Fork shell screens (empty states, app menu, theme refresh) | `Sources/Discourse/UI/` |
| Appearance proxies + `overrideUserInterfaceStyle` | `Sources/Helpers/AppearanceManager.swift` |
| System light/dark → theme refresh | `Sources/Helpers/ColorThemeExtension.swift` |

**Startup sequence.** `main.m` → `VLCAppDelegate.didFinishLaunchingWithOptions:`
registers defaults and bumps `kVLCNumberOfLaunches`. `VLCAppSceneDelegate`
`scene:willConnectToSession:` creates the `UIWindow`, sets
`window.rootViewController = [VLCBottomTabBarController new]`, applies the current
`PresentationTheme`, then calls `VLCAppDelegate.setupTabBarAppearance`, which hands
the tab controller to `VLCAppCoordinator`. The coordinator creates
`TabBarCoordinator` with the shared `MediaLibraryService` and installs the
`VLCPlayerDisplayController` (mini-player) view on top of the tab bar controller.

**Current tabs** (declared in `TabBarCoordinator.setupViewControllers()`, each
wrapped in a `UINavigationController` whose `UITabBarItem` carries an SF Symbol
and a `VLCAccessibilityIdentifier`). The five Rajneesh Discourse destinations, in
order, are:

1. `DiscourseHomeViewController` — `HOME` — `Sources/Discourse/UI/DiscourseHomeViewController.swift`
   (the sectioned home screen arrives in Phase 9).
2. `DiscourseCatalogueViewController` — `DISCOURSES` — `Sources/Discourse/UI/DiscourseCatalogueViewController.swift`
   (the remote catalogue as a full-width list with filters and paging). The
   catalogue is the tab root and has no Discourse/Local switch.
3. `DiscourseSearchViewController` — `SEARCH` — `Sources/Discourse/UI/DiscourseSearchViewController.swift`
   (search field and results in Phase 8).
4. `PlaylistViewController` — `PLAYLISTS` — `Sources/Media Library/MediaViewControllers/PlaylistViewController.swift`
   (the upstream playlist grid and creation flow, themed with the discourse
   accent in Phase 14; the empty-state copy now describes adding from the local
   library).
5. `DiscourseAudioMixerViewController` — `AUDIO_MIXER` (rendered as **Mixer**) — `Sources/Discourse/UI/DiscourseAudioMixerViewController.swift`
   (the control panel, the ordered track list with long-press drag reorder and
   swipe delete, and an empty state whose **Add audio file** action opens the
   system Files picker; the engine is `DiscourseAudioMixer`, §4.12. The removed
   Local Library screen is never linked from the Mixer).

`VideoViewController`, `VLCServerListViewController` and `VLCOnAirViewController`
are **not deleted** — the engine may still open a video file — but they have no
tab and no browsing screen.

Home, Search and the Audio Mixer share `DiscourseScreenViewController`
(`Sources/Discourse/UI/DiscourseScreenViewController.swift`: themed background,
Settings menu bar button, theme refresh) and `DiscourseEmptyStateView`
(symbol, heading, copy, optional action). Home and the Audio Mixer deliberately
carry **no navigation title**: their name lives in the tab bar, and both screens
use `largeTitleDisplayMode = .never`, so content starts under a compact bar. The
catalogue is a plain `UIViewController` with the same chrome (the
`DiscourseEmptyStateView` is also its empty/error state) because it owns a
collection view.

The device media library is **not** a tab. The mixer empty state and local
media shortcuts open `DiscourseLocalLibraryViewController` above the catalogue
in the Discourses navigation stack. It is an `AudioViewController` reduced to a
Songs and Folders pages; its library actions and empty folder picker remain available.
`TabBarCoordinator.showLocalLibrary(pushing:)` can also push an album from that
page. Back returns to the catalogue.

Website links (`/discourses/{id}` and `/discourses/{id}/tracks/{audioId}`) are
Universal Links: `VLCAppCoordinator.handleDiscourseDeepLink:` queues the URL
until `setTabBarController:` completes, then `TabBarCoordinator` selects the
Discourses tab, installs the catalogue root, resolves the discourse from the
history/registry cache (then a catalogue search by title, or its track list as a
last resort; the API has no fetch-by-id route) and pushes
`DiscourseDetailViewController`. A track link passes
`highlightedAudioID`, which scrolls the loaded table to that row once. The
website must serve the AASA file described in §3.8.

The selected tab is persisted under `UserDefaults` key `TabBarIndex`
(`kVLCTabBarIndex`) as the flat index (0 Home, 1 Discourses, 2 Search, 3 Playlists,
4 Audio Mixer); `updateTabBarIndexIfNeeded()` clamps it and `didSelect` writes it
back. The iPad sidebar shows the same five entries — the audio sub-page
flattening is gone. Settings is **not** a tab: it is presented modally from the
left bar button (`AppMenuBarButtonItem`,
`Sources/UI Elements/Buttons/AppMenuBarButtonItem.swift`), whose menu offers only
**About Rajneesh Discourse** and **Settings** (the upstream *Donate* item and the
fork's former *Help & Website* link were removed). The bar button draws the
rounded app icon (the Osho artwork from `LaunchIcon`), not the upstream VLC cone. On
**Home** the logo is static and the same menu opens from a chevron on the right
(`AppLogoBarButtonItem` + `AppMenuBarButtonItem.Style.dropdown`); the other tabs
  keep the icon-as-menu button. About shows an **Acknowledgements & Disclaimer**
  link directly under **Website and help**, jumping to the acknowledgements,
  disclaimer, reporting contact and existing credits and license notices. The
  in-app screen is the fork's `SettingsController`/
`SettingsSection` model (not the legacy InAppSettingsKit plists); Phase 15 added
**Playback history** there and removed the video fullscreen, video resume, video
decoding and subtitle rows from both the model and `Settings.bundle`.
Privacy, Video, Subtitles, Podcasts and Network sections are also omitted from
the in-app settings section list; their underlying preferences remain unchanged.

Screens are pushed with `navigationController?.pushViewController(_:animated:)`.
There is **no main storyboard** (shell is programmatic); only
`Resources/iOS/Launch Screen.storyboard` plus ~35 legacy XIBs exist.

**Tab bar.** On iPhone the system's `UITabBar` is used unmodified: iOS 26
renders it as the floating Liquid Glass capsule (the app must stay in the default
tab-bar mode on iPhone — `.tabSidebar` is an iPad-only layout), while iOS 15–18
show the classic bar. `TabBarCoordinator.updateTheme()` tints the selected item
with `DiscourseColors.accent` and the rest with the secondary text colour on
every version. Fork scroll views add `discourseFloatingTabBarInset`
(`Sources/Discourse/UI/DiscourseFloatingTabBar.swift`) to their bottom inset on
iOS 26, because the floating bar overlays content instead of sitting below it.
The mini player and the edit toolbar still anchor to the tab bar's top.

**Theming.** `PresentationTheme.current` (`brightTheme`, `darkTheme`,
`blackTheme`) drives `ColorPalette` — semantic colours defined as hex literals in
Swift, **not** asset-catalog color sets (the iOS `Images.xcassets` has images
only). Changing the theme posts `.VLCThemeDidChangeNotification`
(`"themeDidChangeNotfication"`, note the upstream spelling). The persisted key is
`kVLCSettingAppTheme` (`@"darkMode"`); this fork registers
`kVLCSettingAppThemeDark` as the first-launch default (Phase 2). The global
override is applied in `AppearanceManager.setupUserInterfaceStyle`.

Fork-only screens do **not** use `ColorPalette`. They use `DiscourseColors`
(same file), a struct of the brief's exact design tokens with `.light`/`.dark`
variants resolved through `DiscourseColors.current`. It mirrors the Android
reference's `values/` and `values-night/` colour resources, so both apps match,
and it follows the existing theme switch. `ColorPalette` is left untouched.

### 4.2 Playback subsystem

**One `VLCMediaPlayer`, owned by `VLCPlaybackService`**
(`Sources/Playback/Control/VLCPlaybackService.{h,m}`, Swift name `PlaybackService`,
singleton `+sharedInstance`).

- The service creates a `VLCMediaListPlayer` and takes
  `_mediaPlayer = _listPlayer.mediaPlayer`; it sets itself as
  `VLCMediaPlayerDelegate`, `VLCMediaListPlayerDelegate` and `VLCMediaDelegate`.
- Public API (see the header for the full list): `playMediaList:firstIndex:subtitlesFilePath:`,
  `configurePlaybackWithMediaAtIndex:fromMediaList:`, `playItemAtIndex:`,
  `startPlayback`/`stopPlayback`, `playPause`/`play`/`pause`, `next`/`previous`,
  `jumpForward:`/`jumpBackward:`, `repeatMode`, `shuffleMode`, `playbackRate`,
  `audioDelay`, `playbackPosition`, `startPosition`, `metadata`, `mediaList`,
  `isNextMediaAvailable`, `stopAfterCurrentItem`, sleep timer, equalizer, PiP,
  renderer, `playerDisplayController`.

**Queue.** There is no separate queue class. The queue is a `VLCMediaList`
(`VLCPlaybackService.mediaList`, plus a `shuffledList`) handed to the
`VLCMediaListPlayer`. Automatic advancement arrives via
`mediaListPlayer:nextMedia:`, which updates `_currentIndex` and posts
`VLCPlaybackServicePlaybackDidMoveOnToNextItem`. `nextMediaIndex:` decides
repeat/shuffle behaviour. The canonical "play these items" entry point for library
media is `VLCPlaybackService+MediaLibrary.m`:
`playMediaAtIndex:fromCollection:` → `configureMediaListWithMLMedia:` → `VLCMediaList`
→ `playMediaList:firstIndex:`. **Discourse playback must reuse this path.**

**States & notifications** (declared `VLCPlaybackService.h:18-31`):
`...PlaybackDidStart`, `...PlaybackDidPause`, `...PlaybackDidResume`,
`...PlaybackWillStop`, `...PlaybackDidStop`, `...PlaybackDidFail`,
`...PlaybackMetadataDidChange`, `...PlaybackRateDidChange`,
`...PlaybackPositionUpdated`, `...PlaybackModeUpdated`,
`...ShuffleModeUpdated`, `...PlaybackDidMoveOnToNextItem`,
`...SleepTimerDidChange`, `VLCLastPlaylistPlayedMedia`.

**Metadata / lock screen.** `VLCMetaData`
(`Sources/Playback/OS Integration/VLCMetadata.{h,m}`) is the single place that
writes `MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo`
(`-populateInfoCenterFromMetadata`). Title/artist/album/artwork come either from a
library `VLCMLMedia` (`isLibraryMedia`) or from libvlc's metadata dictionary
(`fillFromMetaDict:`). Remote commands live in
`VLCRemoteControlService` (`Sources/Playback/OS Integration/VLCRemoteControlService.{h,m}`),
instantiated once by `VLCAppCoordinator`; it enables/disables commands on
`...PlaybackDidStart`/`...PlaybackDidStop` and handles
play/pause/stop/next/previous/skip/rate/position/shuffle/repeat.

**Background audio.** `UIBackgroundModes` contains only `audio`
(`Resources/iOS/Info.plist`); the podcast `fetch`/`processing` modes and
`BGTaskSchedulerPermittedIdentifiers` were removed with the unreachable podcast
background refresher. `VLCPlaybackService` activates the shared
`AVAudioSession` immediately before `_playNewMedia` and before a resume `play`,
because the full player only activated it in its own `viewDidLoad` after
playback had started; without this, the first track could report playing while
silent until pause/play. `VLCPlaybackService` observes
`AVAudioSessionInterruptionNotification`, `AVAudioSessionRouteChangeNotification`,
and `UIApplicationWillResignActive/DidEnterBackground/WillEnterForeground`.
Interruption handling pauses/resumes `_mediaPlayer`; route changes pause when an
external device disconnects. **There is no `AVAudioSession.setCategory:` call in
app code** — audio session configuration is owned by VLCKit/libvlc. There is also
**no** `AVAudioSessionMediaServicesWereReset` handling upstream. Background
playback continues by default (`BackgroundAudioPlayback` default `YES`).

**Mini player.** `VLCPlayerDisplayController` owns and shows/hides the mini player.
The view is `VLCAudioMiniPlayer` (`Sources/Playback/Player/MiniPlayer-iOS/`),
which conforms to the `VLCMiniPlayer` protocol and `VLCPlaybackServiceDelegate`.
`VLCPlayerDisplayController` is added as a subview of the tab bar controller in
`VLCAppCoordinator`, anchored to the tab bar's real top/bottom anchors.

**Full player.** `PlayerViewController.swift` is the shared base class; the
concrete controllers are `AudioPlayerViewController` (audio full-screen) and
`VideoPlayerViewController` (video full-screen), both instantiated and presented
by `VLCPlayerDisplayController` in a `VLCPlaybackNavigationController`
(full-screen modal). The audio player's `MediaNavigationBar` (a `UIStackView`)
carries one fork-only arranged subview before the more-options button: the
discourse like control (`DiscourseLikeControl`, §4.9), which
`AudioPlayerViewController` inserts, hides for non-discourse media and refreshes
from the playback and likes notifications. Buffering uses a plain white
`UIActivityIndicatorView`; the VLC pulsing cone remains only on the upstream
podcast/network loading screens.

### 4.3 Local media library

- **No app-side database layer.** The library is libvlc's `libvlc_media_library`
  C API exposed through the SPM package **VLCMediaLibraryKit**
  (`VLCMediaLibrary`, `VLCMLMedia`, `VLCMLAlbum`, `VLCMLArtist`, `VLCMLPlaylist`,
  `VLCMLGenre`, `VLCMLFolder`). Storage is a SQLite DB managed by the kit at
  `Library/MediaLibrary/medialibrary.db` (+ thumbnails/internal/cache dirs).
- Central service: **`MediaLibraryService`**
  (`Sources/Media Library/MediaLibraryService.swift`) — setup, discovery, all
  fetch/query methods, create/delete playlist, save playback state, and the
  `MediaLibraryObserver` fan-out.
- The Discourses tab's Local Songs empty state checks for a resolvable external
  folder bookmark. If one exists it says **No files found** and offers
  **Add External Folder**; otherwise it prompts the user to add a folder. Both
  use the library header's document picker and `addExternalFolder(at:)` flow.
  iOS has no global permission for scanning local audio; access is granted per
  external folder through the picker, so there is no separate system permission
  prompt/status to display.
- View models: `Sources/Media Library/MediaLibraryModel/` (`MLBaseModel` +
  `MediaModel`, `TrackModel`, `AlbumModel`, `ArtistModel`, `PlaylistModel`,
  `GenreModel`, `FolderModel`, `HistoryModel`, …).
- Category screen controllers: `Sources/Media Library/MediaCategories/` and
  `Sources/Media Library/MediaViewControllers/`.
- Playlists: `VLCMLPlaylist` via `MediaLibraryService`; UI in
  `PlaylistCategoryViewController`, `AddToCollectionViewController`, `EditActions`.
- Favourites/history: media-library favourites (`VLCMLMedia.isFavorite()`,
  `MediaResolver.setFavorite`), network favourites (`VLCFavoriteService` →
  `Favorites.plist`), and playback history inside the media-library DB
  (`audioHistory()`/`videoHistory()`, `HistoryModel`).

### 4.4 Networking and persistence primitives

- **HTTP:** `VLCHTTPClient` (`Sources/Network/HTTP/VLCHTTPClient.{h,m}`) built on
  `NSURLSessionConfiguration.defaultSessionConfiguration`, JSON via
  `NSJSONSerialization`. Server/UPnP/Plex browsing uses `NSXMLParser`.
  There is **no** AfNetworking/Alamofire and **no** existing JSON disk cache.
- **Downloads:** `VLCTransferController` / `VLCHTTPFileDownloader` /
  `VLCMediaFileDownloader` (`Sources/Network/Download/`).
- **Images:** `VLCThumbnailsCache` (memory + disk), `VLCNetworkImageView`.
- **Analytics:** Firebase Analytics (without advertising ID support) initializes
  in `VLCAppDelegate` and collects its automatic events. Place the Firebase
  `GoogleService-Info.plist` for `com.oshodiscourse` at
  `Resources/iOS/GoogleService-Info.plist` before building; it is gitignored.
- **Crash/error reporting: none.** No Sentry or Crashlytics in this repo.
  Logging is `APLog(...)` → `NSLog` (`Sources/Headers/VLC-iOS-Prefix-Header.pch`).
  The discourse layer adds a small `DiscourseDiagnostics` logger (§9) instead of a
  crash reporting SDK — see §11.
- **UserDefaults** for all app settings; keys are `#define`s in
  `Sources/Headers/VLCConstants.h` and registered in `VLCAppDelegate.m`.
- **Keychain** via `KeychainCoordinator`
  (`Sources/Helpers/KeychainCoordinator.swift`, backed by the `XKKeychain` SPM
  package). Existing services: `org.videolan.vlc-ios.passcode`,
  `org.videolan.vlc-ios.parentalControl`. **The anonymous user UUID uses this.**
- **Files:** `Favorites.plist` / `Radio.plist` (`NSCoding`), last-played `.m3u`
  in Application Support, settings JSON export in Documents.

### 4.5 Onboarding, About, localisation

- **Onboarding:** `Sources/Onboarding/VLCFirstSteps*.{h,m,xib}` (a `UIPageViewController`
  of pages). Auto-presented from `MediaCategoryViewController.viewDidAppear` →
  `showGuideOnLaunch()` when `UserDefaults` `hasLaunchedBefore`
  (`kVLCHasLaunchedBefore`) is `false`.
- **Launch screen:** `Resources/iOS/Launch Screen.storyboard` shows the app icon
  (`LaunchIcon.imageset`, a rounded export of the 1024 launcher artwork) centred
  on the dark app background (`#0D0D0D`). It is static (no code), so the icon is
  baked into the asset catalog; `DiscourseLaunchScreenTests` keeps the name and
  asset wired.
- **About:** `Sources/About/AboutController.swift` renders
  `Sources/About/iOS/About Contents.html` in a `WKWebView`, substituting
  `VLCICONIMAGESOURCE` (now `AppIcon-480x480.png`, the branded app icon),
  `VLCFORIOSVERSION`, `VLCKITVERSION`, `TEXTCOLOR`, `BACKGROUNDCOLOR`. The old
  VLC wordmark navigation title is removed. Links open externally. Presented
  from `AppMenuBarButtonItem`.
  (tvOS uses `Sources/About/VLCAboutViewController.m` + `Sources/About/tvOS/About Contents.html`.)
- **Localisation:** plain `NSLocalizedString` over
  `Resources/<lang>.lproj/Localizable.strings` (~65 languages). Base language `en`
  (`Info.plist: CFBundleDevelopmentRegion`). Settings strings live in a separate
  table (`Resources/iOS/Settings.bundle/<lang>.lproj/Root.strings`).
- **App name / bundle id:** `Resources/iOS/Info.plist` (`CFBundleDisplayName` = `VLC`,
  `CFBundleName` = `VLC for iOS`), `Buildsystem/SharedConfig.xcconfig`
  (`BUNDLE_IDENTIFIER_PREFIX=com.example`), `project.pbxproj`.

### 4.6 Dependencies (pinned)

- **VLCKit**: local binary package `Buildsystem/RNNoise`, built from patched
  `4.0.0-a25` sources; exact revisions and commands are in §3.7.
- **SPM** (`Package.resolved`): **VLCMediaLibraryKit `0.15.0-b2`**, XKKeychain `1.0.3`, pcloud-sdk-swift `3.2.3`,
  CocoaHTTPServer `2.4.2`, InAppSettingsKit `3.7.1`, OBSlider `1.1.3`,
  GRKArrayDiff `1.1.2`, MarqueeLabel `4.5.3`.
- **CocoaPods** (`Podfile.lock`): box-ios-sdk-v2, ObjectiveDropboxOfficial
  (plus their transitive dependencies). Targets: `VLC-iOS`, `VLC-iOS-no-watch`,
  `VLC-iOSTests`.

### 4.7 Discourse API layer (`Sources/Discourse/API/`)

Fork-only, Foundation-only code with no UIKit dependency, so the models, the URL
resolver and the cache are testable without a running app.

| Concern | File |
|---|---|
| Endpoints, cache policy, request plumbing | `DiscourseAPIClient.swift` |
| Payload structs (`Discourse`, `DiscourseAudio`, envelopes, requests) | `DiscourseModels.swift` |
| HTTPS-only URL resolution against the CDN | `DiscourseURLResolver.swift` |
| 24 h / 10 MB on-disk payload cache | `DiscourseAPICache.swift` |
| Anonymous install UUID (keychain + UserDefaults) | `DiscourseIdentity.swift` |
| Error classification + user copy | `DiscourseAPIError.swift`, `DiscourseErrorCopy` |
| Telemetry-free diagnostics | `DiscourseDiagnostics.swift` |

**Client behaviour.** `DiscourseAPIClient.shared` talks to
`RD_API_BASE_URL` with `x-api-key: RD_API_KEY` on every request. Public methods:
`discourses(page:search:isAudioCleaned:language:sort:forceRefresh:)`,
`discourseAudios(page:search:discourseName:language:sort:forceRefresh:)`,
`discourseTracks(discourseID:forceRefresh:)`, `likes()`,
`likeDiscourse(id:)`/`likeAudio(id:)`, `unlikeDiscourse(id:)`/`unlikeAudio(id:)`,
`recordStats(discourseID:audioID:)`, `discourseStats(...)`, `audioStats(...)`.

- Successful GETs are served from `DiscourseAPICache` while fresh (24 h); a force
  refresh sends `Cache-Control: no-cache` and hits the network.
- Transport failures and 5xx answers serve stale cache when present, otherwise the
  call throws `DiscourseAPIError`. Cached payloads are never deleted on error.
- `/likes` is never cached (user specific), whatever the caller passes.
- Cancellation surfaces as `.cancelled` and never falls back to cache.
- Errors are logged through `DiscourseDiagnostics` without the key, the user UUID
  or payload bodies. `userMessage` is always the generic server copy.

**Identity.** `DiscourseIdentity.shared.userID` generates one lowercase UUID per
install, stores it in the keychain service
`online.sandalbar.rajneesh-discourse.identity` (via `XKKeychainGenericPasswordItem`,
the same mechanism as the passcode) and mirrors it to `osho_api_user_id`. A lost
keychain copy is restored from the defaults mirror and vice versa.

**Cache storage.** `Caches/DiscourseAPI/` (excluded from backup), one JSON file
per request URL keyed by SHA-256, freshness taken from the file's modification
date, oldest entries evicted past 10 MB.

### 4.8 Discourse stores (`Sources/Discourse/Stores/`)

Fork-only persistence, one `final class` singleton per concern, all built on
`DiscourseSettings` (a typed `UserDefaults` wrapper that turns corrupt JSON into
"no value"). Each store guards its state with a private serial `DispatchQueue`,
accepts an injected `DiscourseSettings`, service, date provider and
`NotificationCenter` for tests, and broadcasts changes through the names in
`DiscourseNotifications.swift` (`.discourseLikesDidChange`,
`.discourseHistoryDidChange`, `.discoursePlaybackProgressDidChange`).

| Store | Responsibility |
|---|---|
| `DiscourseSettings` | JSON / primitive / string-set access, defensive decoding. |
| `DiscourseNotifications` | The change notification names (likes, history, playback progress, downloads, mixer). |
| `DiscourseLikesStore` | Liked sets, optimistic toggles with rollback, pending map, 7-day `GET /likes` gate. |
| `DiscourseHistoryStore` | Recently played discourses/tracks, newest first, deduped, max 24. |
| `DiscourseStatsStore` | 24 h `POST /stats` dedupe, marked only after success. |
| `DiscourseStatsCache` | Weekly top discourses/tracks, 3 h TTL, stale-on-failure. |
| `DiscoursePlaybackStore` | Resume positions, completion, progress fractions, "played" flag, track index. |
| `DiscourseCatalogueFilterStore` | Last language/sort filter. |
| `DiscoursePlaybackSettings` | Reads the fork's `playback_history` switch (default on). |

**Service seams.** `DiscourseLikeService` and `DiscourseStatsService` are
protocols that `DiscourseAPIClient` conforms to, so stores are testable without a
network (`Buildsystem/Testing/Unit/DiscourseStoresTests.swift`). The history and
playback stores stay pure persistence primitives: the 60-second qualification
and the playback-history setting are enforced by the caller (Phase 10), except
for the discourse-open entry Home needs now.

**Stats refresh.** `DiscourseStatsCache` asks its service with
`forceRefresh: true` whenever its 3 h TTL expires (and for windows other than
`7_days`), so the API layer's 24 h payload cache cannot silently extend the
weekly lists. The API layer's stale-on-failure fallback still applies.

**Likes semantics.** A toggle updates membership and count immediately, then the
request settles: success adopts the server's `total_likes`, failure restores the
previous membership/count and rethrows so the UI can show
`DiscourseErrorCopy.likeFailure`. Pending targets survive a relaunch; a
successful refresh clears them.

### 4.9 Discourse UI layer (`Sources/Discourse/UI/`)

Fork-only, UIKit, dark-first. Every screen paints `DiscourseColors.current`
(§4.1), observes `.VLCThemeDidChangeNotification` and refreshes in place.

| Concern | File |
|---|---|
| Shell base (background, Settings bar button, theme refresh) | `DiscourseScreenViewController.swift` |
| Empty state (symbol, heading, copy, optional action) | `DiscourseEmptyStateView.swift` |
| Catalogue list, paging, filters, loading/empty/error states | `DiscourseCatalogueViewController.swift` |
| Discourse card (tile and list layouts: artwork, title ≤2 lines, language, track count, heart) | `DiscourseCardCell.swift` |
| Compact counts (`999` / `1.2k` / `12k` / `1m`) | `DiscourseCountFormatter.swift` |
| Language names, track/like counts, summary line, durations | `DiscourseTextFormatting.swift` |
| Discourse detail (header, track rows, play all, track menu) | `DiscourseDetailViewController.swift`, `DiscourseDetailHeaderView.swift`, `DiscourseTrackCell.swift` |
| Search (two sections, debounce, paging, states) | `DiscourseSearchViewController.swift`, `DiscourseSearchCell.swift`, `DiscourseSearchResults.swift` |
| Shared discourse/track row (search + Home) | `DiscourseRowView.swift` |
| Device-library history adapter for Home | `DiscourseLocalTrack.swift` |
| Like control (heart, count, optimistic/pending state, a11y label) | `DiscourseLikeControl.swift`, `DiscourseLikeState` |
| Download control (arrow, progress ring, green tick, failure) | `DiscourseDownloadControl.swift`, `DiscourseDownloadSummary` |
| One download tap/removal/confirmation helper | `DiscourseDownloadActions.swift` |
| One like toggle + failure alert for every surface | `DiscourseLikeActions.swift` |
| Transparent VoiceOver "open" element for cards/rows | `DiscourseAccessibilityButton.swift` |
| Home (four sections, states, stats) | `DiscourseHomeViewController.swift`, `DiscourseHomeContent.swift`, `DiscourseHomeSectionHeaderView.swift`, `DiscourseHomeTrackCell.swift` |
| Audio Mixer screen (panel, ordered list, clear, empty state) | `DiscourseAudioMixerViewController.swift` |

**Catalogue behaviour.** One-column `UICollectionViewCompositionalLayout`: each
item is full width (16 pt section insets) and the row is a self-sizing
`DiscourseCardCell` in its `.list` layout — 88 pt artwork on the left, title
(two lines), language and a footer with the track count, the download badge and
the like control on the right. `DiscourseCardCell` also keeps its `.tile`
layout for the Home carousel (square artwork above the same content); the two
share the heart, badge state and VoiceOver overlay. The cell loads artwork
through the upstream `VLCNetworkImageView` (`VLCThumbnailsCache` memory + disk
cache), so no new image pipeline exists.

- First page loads from the 24 h `DiscourseAPICache` when fresh, from the network
  otherwise; pull-to-refresh is a force refresh (`Cache-Control: no-cache`).
- Paging: the next page is requested when the scroll is within 400 pt of the
  bottom and `page < meta.total_pages`; appended items are deduped by id and
  inserted with `insertItems(at:)` so the list does not flash.
- Filters: a bar-button `UIMenu` with Language (all/English/Hindi) and Sort
  (default/most liked), persisted through `DiscourseCatalogueFilterStore`;
  "Clear filters" appears only while a filter is active. Changing a filter drops
  the rendered rows, resets paging and reloads page 1.
- States: centred spinner (first load), `DiscourseEmptyStateView` (empty
  catalogue with *Reload*, or failure with *Try again* and
  `DiscourseErrorCopy.serverFailure`), and content. A failed request with rows
  already rendered keeps them: the catalogue never empties itself on an error.
- A request token invalidates stale answers when filters change or a retry races
  an in-flight load.

**Cards today** reserve two title lines for consistent heights; catalogue titles
align to the top beside artwork. Cards show artwork, title, language, track count and likes.
control (heart + compact count) in the footer, and the title's counts are seeded
from the payload so the heart is correct before the first tap. While a discourse
has downloads, a small badge counts them (`3/11`: green when finished, accent
while downloading); a card with none shows no badge. In the catalogue's `.list`
layout the badge sits in the footer, between the track count and the heart; the
Home carousel's `.tile` cards keep it over the artwork's corner.

**Detail screen.** Selecting a card pushes `DiscourseDetailViewController`:

- It fetches `discourse-audios?discourse_id=` (no pagination upstream) and sorts
  by `track_number`, then title. The nav bar shows the discourse title.
- The table header shows artwork (128 pt, radius 8), the title, the
  `language · tracks · likes` summary, a filled **Play all** button
  (`discoursePlayAll`) and the discourse's like control. Rows lead with the track
  number inside a progress ring (or the playing speaker, or a checkmark once
  finished), then the title (≤2 lines), the duration, the download control and
  the track's like control.
- The nav-bar download menu (arrow, `discourseDownloadsMenu`) offers **Download
  all**, **Cancel downloads** while any run and **Remove all downloads** while any
  exist; the last one asks first. The row's long-press menu gains **Download**,
  **Cancel download**, **Retry download** or **Remove download** to match the
  track's state.
- Tapping a row queues the whole discourse from that index. The long-press menu
  offers **Play**, **Play next**, **Add to queue** and the track's download
  action.
- The row being played is marked from the track identity the media factory
  attached to the player item (speaker glyph, `accessibilityValue` *Playing*); it
  updates on start/next/stop/fail.
- The progress ring (`DiscourseTrackProgressView`) is fed by
  `DiscoursePlaybackStore.fraction(audioID:)`: the durations are registered when
  the detail loads, and `.discoursePlaybackProgressDidChange` refreshes only the
  affected visible row, so the ring follows the 30 s saves and the completion
  without reloading the table. A finished track shows a checkmark
  (`accessibilityValue` *Played*).
- States mirror the catalogue: spinner on first load, empty state with *Reload*,
  failure state with *Try again* and `DiscourseErrorCopy.serverFailure`. A failed
  refresh with rows already rendered keeps them. Pull-to-refresh is a force
  refresh, and a request token drops stale answers.
- The table's bottom inset grows by `AudioMiniPlayer.height` while the mini player
  is visible (the catalogue list does the same), so the last row scrolls clear of
  it. Both screens observe the `VLCPlayerDisplayController{Display,Hide}MiniPlayer`
  notifications.

**Search behaviour.** The Search tab searches the **remote catalogue only**
(never the device library), over both discourses and tracks.

- The screen is a plain `UIViewController` (like the catalogue) with the shared
  chrome: themed background, Settings bar button, theme refresh. A
  `UISearchController` sits in the navigation bar (`hidesSearchBarWhenScrolling =
  false`), and results are a single-sectioned-when-empty `UITableView`
  (`discourseSearchResults`) with two sections, **Discourses** then **Tracks**,
  each hidden while it has no rows. `DiscourseSearchCell` renders both variants:
  artwork (52 pt, radius 8), title (≤2 lines), and either the
  `language · tracks · likes` summary (discourse) or the discourse name plus the
  duration (track); the playing track's title uses the accent colour.
- Every query fetches `discourses?search=` and `discourse-audios?search=`
  concurrently (page 1) and appends both result lists through
  `DiscourseSearchResults`, which dedupes by id. Paging follows whichever endpoint
  is deeper (`page < max(total_pages)`), loading the same page number from both
  when the scroll is within 400 pt of the bottom. The GETs use the same 24 h cache
  as the catalogue; pull-to-refresh forces a network read.
- Typing is debounced by 350 ms; the keyboard's search key runs the query
  immediately. A request token drops answers for queries the user has already
  replaced, and an empty/cleared field returns to the idle prompt without a
  request.
- States: idle (`SEARCH_EMPTY_TITLE`/`SEARCH_EMPTY_MESSAGE`), centred spinner,
  results, no matches (`SEARCH_NO_RESULTS` + `DISCOURSE_SEARCH_EMPTY_MESSAGE`
  formatted with the query) and failure (*Could not search the catalogue*,
  `DiscourseErrorCopy.serverFailure`, *Try again*). A failed next-page request
  keeps the rendered rows and is retried by the next scroll.
- Tapping a discourse result pushes `DiscourseDetailViewController`. Tapping a
  track starts it through `DiscoursePlayback.play(track:discourse:)`, i.e. the
  one-item queue plus the non-interrupting continuation fetch, so the rest of
  that discourse follows without a second tap. Starting playback presents the
  upstream full-screen player, as everywhere else (§10.24).
- The results table grows its bottom inset by `AudioMiniPlayer.height` while the
  mini player is visible, and marks the playing row from
  `DiscoursePlayback.currentIdentity()`. Cells expose
  `discourseSearchDiscourse` / `discourseSearchTrack` identifiers for UI tests.

**Home behaviour.** The first tab is a plain `UIViewController` (like the
catalogue) with a `UICollectionViewCompositionalLayout`, a navigation-bar
`UIRefreshControl` and the shared chrome. `DiscourseHomeContent` turns the
stores' payloads into sections, in product order, dropping empty ones:

1. **Recently played** — `DiscourseHistoryStore.recentlyPlayedDiscourses`,
   horizontal 160 pt-wide `DiscourseCardCell` carousel (orthogonal scrolling).
2. **Recently played tracks** — the discourse history
   (`recentlyPlayedAudios`) followed by the device library's own playback
   history (`MediaLibraryService.medialib.audioHistory()` through
   `DiscourseLocalTrack`), full-width rows; the section is omitted while
   `DiscoursePlaybackSettings.isHistoryEnabled` is `false`.
3. **Top discourses this week** — `DiscourseStatsCache.discourses(window:
   .last7Days)`, same carousel.
4. **Top tracks this week** — `DiscourseStatsCache.audios(window: .last7Days)`,
   same rows.

- Recently-played discourses are deduped by id and capped at
  `DiscourseHistoryStore.limit` (24). Recently-played tracks dedupe the discourse
  side by id and the library side by file URL (media identity), lead with the
  discourse history and then append the library history, capped together at 24
  (neither list carries timestamps, so a true interleave is not possible; AGENTS
  §10.29). The weekly lists are deduped but not capped (the backend returns a
  short list).
- Section headers use `DiscourseHomeSectionHeaderView` (title3, `.header`
  trait). Track rows are `DiscourseHomeTrackCell` hosting the same
  `DiscourseRowView` as the search results, so artwork (52 pt), title (≤2
  lines), discourse name and duration line up across both screens.
- Tapping a discourse card pushes `DiscourseDetailViewController`; tapping a
  discourse track starts it through `DiscoursePlayback.play(track:discourse:)`;
  tapping a library track calls the upstream
  `PlaybackService.playMedia(at:fromCollection:)`, so its metadata, history and
  mini player behave exactly as in the local library. Library rows hide the like
  and download controls, start at the card's leading edge when the file has no
  artwork, and show `artist · duration`.
- Opening a detail records the discourse in `DiscourseHistoryStore` (newest
  first) when history is enabled, so *Recently played* reflects what the user
  opened even before the 60-second track qualification exists (Phase 10).
- Loading: the history is read synchronously from `UserDefaults` and rebuilt on
  every `viewWillAppear` and on `.discourseHistoryDidChange`; the two weekly
  lists load concurrently through `DiscourseStatsCache`. Pull-to-refresh forces
  both lists and rebuilds the history section.
- States: centred spinner while nothing is available and the first stats request
  runs; the empty state (`HOME_EMPTY_TITLE` / `HOME_EMPTY_MESSAGE`) when every
  section is empty; *Could not load the top lists* with *Try again* when the
  stats request failed and there is no history to show. A stats failure with
  history rendered keeps the history sections.
- A request token drops stale stats answers when a refresh races the first load;
  the playing row is marked from `DiscoursePlayback.currentIdentity()` (discourse
  rows) or the currently playing media's URL (library rows) and only while
  `PlaybackService.isPlaying`, and the grid grows its bottom inset by
  `AudioMiniPlayer.height` while the mini player is visible. The collection
  exposes the `discourseHome` identifier and track rows `discourseHomeTrack` for
  UI tests.

**Likes behaviour.** `DiscourseLikeControl` shows the heart and a compact count
only when the count is positive; discourse metadata summaries also omit zero likes. It is the one
renderer; `DiscourseLikeState.resolve(target:payloadLikes:store:)` decides what it
shows (the store's optimistic count wins over the payload count). It is drawn on:

- catalogue cards and the Home card carousel (footer),
- the discourse detail header (next to **Play all**) and every track row,
- search and Home track rows (trailing; the duration moved into the metadata
  line, then the download arrow, then the heart),
- the full audio player's navigation bar, inserted before the more-options
  button. It is hidden unless the current media carries a discourse identity
  whose payload is still in `DiscourseTrackRegistry`, and it updates on
  start/next/stop/fail and on `.discourseLikesDidChange`.

Every list seeds counts with `DiscourseLikesStore.updateCount` when a payload
arrives. A tap calls `DiscourseLikeActions.toggleDiscourse`/`toggleAudio`, which
uses the store's optimistic toggle; `.discourseLikesDidChange` then reconfigures
only the visible cards/rows (the catalogue list, the detail header + visible rows,
the search rows, the Home cells) and a failed request rolls the store back and
shows `DiscourseErrorCopy.likeFailure` in an alert. Likes are independent of the
playback-history switch. `TabBarCoordinator` refreshes `GET /likes` on launch and
on every foreground; the store's seven-day window makes that cheap.

Accessibility: a card or row is now a **container**, not one merged element. A
transparent `DiscourseAccessibilityButton` (label = title + metadata, button
trait, `accessibilityActivate()` opens the discourse/starts the track) sits under
the like control, so VoiceOver can focus and activate *both* the row and its
heart. The heart's label follows the spec (`Like {title}. {n} likes` /
`Unlike {title}. {n} likes`), reports *Updating* (`accessibilityValue`) while a
request is in flight, and expands its touch target to 44 pt without changing its
visual size.

---

### 4.10 Discourse playback bridge (`Sources/Discourse/Playback/`)

Fork-only code that feeds discourse tracks into the **existing** playback
pipeline. There is no second player, no second queue type and no fork of
`VLCPlaybackService`; the layer only builds `VLCMedia` objects and a
`VLCMediaList`, then calls the upstream entry point.

| Concern | File |
|---|---|
| Track → `VLCMedia` mapping and queue construction | `DiscourseMediaFactory.swift` |
| Queue start, continuation, play next / add to queue, current item | `DiscoursePlayback.swift` |
| Resume/qualification/save/completion rules (no player) | `DiscoursePlaybackProgress.swift` |
| Notification glue, stats reports, history recording | `DiscoursePlaybackTracker.swift` |
| Bounded in-memory payload registry (tracks, discourses) | `DiscourseTrackRegistry.swift` |

**Mapping** (`DiscourseMediaFactory.media(for:discourse:fallbackTrackNumber:)`),
per AGENTS §6.3:

- URL: resolved remote `audio_url` today; Phase 12 will prefer a verified local
  download.
- `title` = track title (localised `Track %d` fallback), `artist` = `Osho`,
  `album` = discourse title (else the track's `discourse_name`), `trackNumber`,
  `artworkURL` = resolved discourse thumbnail, `length` = `duration_seconds`.
- Identity: the libvlc meta extras `rd.discourseID` / `rd.audioID`, plus a record
  in `DiscourseMediaIdentityStore` (URL → identity). A queue restored from the
  last-played `.m3u` has no extras, so `identity(of:)` falls back to the URL
  index.
- `VLCMetaData.fillFromMetaDict:` reads these fields, so the mini player, the
  full player and the lock screen show the right title/artist/album/artwork
  without changes to `VLCMetadata`.

**Queue.** `DiscourseMediaFactory.mediaList(for:discourse:startingAt:)` drops
tracks without a usable URL and returns the queue plus the index playback must
start at (aligned with the requested track, never past the end).
`DiscoursePlayback.play(tracks:discourse:startingAt:)` adds the upstream
`mediaOptionsDictionary` to every item and calls
`PlaybackService.sharedInstance().playMediaList(_:firstIndex:subtitlesFilePath:)`,
so next/previous, shuffle, repeat, the mini player, the queue screen, background
audio, remote commands and the sleep timer behave exactly as for library media.

**Continuation.** `play(track:discourse:)` starts a one-item queue immediately
(for entry points that know a single track, used from Phase 8 on) and then fetches
`discourse-audios?discourse_id=`. If the same list is still playing, it appends
the missing tracks to both `mediaList` and `shuffledList` without interrupting
playback (the same mutation upstream uses for *Enqueue*). If the user started
something else meanwhile, the continuation is dropped.

**Track actions.** `playNext(_:discourse:)` inserts after the current item (both
lists), `appendToQueue(_:discourse:)` appends (both lists); with nothing playing
both degrade to normal playback. `currentIdentity()` reads the identity from
`currentlyPlayingMedia`.

**Not in this layer yet** (Phases 11–12): likes on rows and local downloads. They
reuse the identity above.

**Resume, progress, completion and qualification (Phase 10).**
`DiscoursePlaybackTracker.shared` is started once from
`TabBarCoordinator.setup()` (`Task { @MainActor … }`) and observes the upstream
playback notifications. `DiscoursePlaybackProgress` holds the rules without a
player, so they are unit-tested directly:

- **Ticks.** `VLCPlaybackServicePlaybackPositionUpdated` is the tick source.
  Each sample advances the accumulated playback time by the position delta only
  while `VLCPlaybackService.isPlaying` is true, so pause, buffering and stop time
  never count; deltas above 3 s are seeks and are ignored, as are negative ones.
- **Qualification.** A play qualifies after 60 s of accumulated playback; the
  tracker then records the track in `DiscourseHistoryStore`, records its
  discourse when the payload is known, and posts `POST /stats` once per track per
  24 h through `DiscourseStatsStore` (marked sent only after a successful
  response). Both are skipped while `DiscoursePlaybackSettings.isHistoryEnabled`
  is false. A restored queue with no payload is fetched once from
  `/discourse-audios` before the history entry is written.
- **Saves.** The resume point is written to `DiscoursePlaybackStore` every 30 s of
  playback and on pause, stop, next item, failure and when the app resigns
  active/enters the background.
- **Completion.** Reaching within 1 s of the end marks the track completed; a
  completed track is not completed twice. Starting a completed track from its
  start clears the flag (replay-from-start).
- **Resume.** `DiscoursePlayback.play(tracks:discourse:startingAt:)` sets
  `VLCPlaybackService.startPosition` to the stored fraction of the item it starts
  at (never below 1 s, never into the last 5 s, capped at 0.98) before calling
  `playMediaList`; later queue items start at the beginning. A track marked
  completed is not resumed.
- **Payloads.** `DiscoursePlayback` registers every queued track and discourse in
  `DiscourseTrackRegistry` (bounded to the 256 most recent) and registers the
  durations in `DiscoursePlaybackStore`, so the detail rings work before a track
  plays. The registry is in memory only.
- **Player values.** `playbackPosition` is a 0…1 fraction, so the tracker scales
  it by `mediaDuration` (milliseconds) and falls back to the stored duration while
  libvlc has not reported one.

### 4.11 Discourse downloads (`Sources/Discourse/Downloads/`)

Fork-only. Downloads are an optimisation over streaming, never a second player:
`DiscourseMediaFactory` hands the local file to the same `VLCMediaList` when one
is verified. The layer splits durable bookkeeping from the transfer so the store
is testable without a network.

| Concern | File |
|---|---|
| Durable records, files, verified local URLs, pruning | `DiscourseDownloadStore.swift` |
| Background `URLSession`, queue, progress, cancel/remove, reattachment | `DiscourseDownloadManager.swift` |
| One download affordance for rows (arrow, ring, green tick, failure) | `DiscourseDownloadControl.swift` |
| One tap/menu/confirmation helper for every surface | `DiscourseDownloadActions.swift` |

**Storage.** `Application Support/Discourses/<audioID>.audio` (backup excluded),
plus two `UserDefaults` JSON maps (§7): audio id → filename and audio id →
discourse id. `localURL(for:)` answers only when the file exists and its size is
greater than zero, so a truncated or externally deleted file silently falls back
to the CDN. On every launch the store drops records whose file vanished and
deletes files no record mentions, so neither side can leak. Filenames are
sanitised to alphanumerics, `-`, `_` and `.`.

**Transfer.** `DiscourseDownloadManager` owns one background session
(`online.sandalbar.rajneesh-discourse.downloads`, `sessionSendsLaunchEvents`),
runs at most three tracks at once and keeps the rest in a pending list. A task's
`taskDescription` is `audioID|discourseID`, so a download that outlived the app
is re-attached to its track after relaunch (`getAllTasks`). Progress is reported
through `.discourseDownloadsDidChange` at most once per 2%, and the notification
always arrives on the main thread. States are `missing`, `downloading(progress)`,
`downloaded` and `failed`; a failure keeps an exclamation icon and a retry until
the track is retried or removed, and is reported once (the icon plus its
accessibility label), never as a repeating alert. `VLCAppDelegate` forwards
`application:handleEventsForBackgroundURLSession:completionHandler:` to
`DiscourseDownloadManager.handleBackgroundEvents(identifier:completionHandler:)`,
which releases the system's handler once the session has delivered every event.

**UI.** Every track row carries a `DiscourseDownloadControl` before the heart:
outlined arrow (stream), determinate ring (downloading), green filled arrow
(downloaded), exclamation (failed). A tap downloads, cancels or retries; a
downloaded track is never deleted by a tap. Removing is a context-menu action on
the row (detail) and the detail screen's nav-bar download menu, which offers
**Download all**, **Cancel downloads** while any run, and **Remove all
downloads** while any exist — the last one confirms with *"Remove all downloaded
tracks from this discourse?"*. Catalogue and Home cards show a small badge over
the artwork (`3/11`, green when finished, accent while downloading) instead of a
footer row, so the fixed-height Home carousel cannot clip. Every screen observes
`.discourseDownloadsDidChange` and reconfigures only the visible rows/cards.

### 4.12 Audio Mixer (`Sources/Discourse/Mixer/`)

Fork-only. The second channel is a dedicated `VLCMediaPlayer`, because VLCKit
exposes one player per instance (AGENTS §10.4). It never touches the main
queue, the mini player or the now-playing info; it only listens to the main
player's notifications.

| Concern | File |
|---|---|
| Engine: membership, follow logic, fades, audio session | `DiscourseAudioMixer.swift` |
| Control panel (on switch, now playing, play/pause, loop, volume) | `DiscourseMixerPanelView.swift` |
| Track row (title, selected checkmark, "Playing in the mixer") | `DiscourseMixerTrackCell.swift` |
| Document-picker import into app-owned storage | `DiscourseMixerFileImporter.swift` |
| Screen: panel header, ordered list (long-press drag reorder, swipe delete), empty state | `Sources/Discourse/UI/DiscourseAudioMixerViewController.swift` |

**Storage.** The documented keys (§7): `audio_mixer_files` is the ordered array
of file URL strings, `audio_mixer_selected` the selected URL, and
`audio_mixer_enabled` / `audio_mixer_loop` / `audio_mixer_volume` the switches and
volume (defaults `false` / `true` / `50`, volume clamped to 1…100). The selection
is stored as the URL rather than an index so reordering can never select the
wrong track; a missing selection falls back to the first item. Rows are titled
with the file name (the brief's keys store URLs, not library metadata), and a
deleted file simply fails to load without crashing.

**Follow behaviour.** The engine is created at launch (`TabBarCoordinator`) so a
previously enabled mixer works before its tab is opened. It observes the main
player's `DidStart` / `DidResume` / `DidPause` / `WillStop` / `DidStop` / `DidFail`
notifications:

- start: 250 ms after the main player starts, only when the mixer is enabled and
  the main player is audio (`numberOfVideoTracks == 0` or `playAsAudio`); a video
  stops the mixer instead;
- pause: fade out ~220 ms then pause the mixer's player;
- stop/fail: fade out then stop and mark the item for a reload on next start;
- a track end (`VLCMediaPlayerStateStopped` without a requested stop) loops when
  **Loop track** is on, else leaves the mixer stopped.

The panel's play button enables the mixer but only plays while the main player
is playing audio. Delayed starts and restarts recheck the main player's state.

**Audio session.** The mixer shares the app's single playback session (VLCKit
owns `AVAudioSession`). Interruptions pause it and resume after
`shouldResume` when the main player is playing; losing the output device pauses
it; a media-services reset pauses the main player, drops the mixer's player and
lets the follow logic rebuild it. Volume 1…100 maps straight onto VLC's 0…200
scale and is only ever written by the mixer.

**Entry point.** The Mixer's **+** button and its empty-state **Add audio file**
action present `UIDocumentPickerViewController` for `.audio` files.
`DiscourseMixerFileImporter` copies the selection into
`Application Support/AudioMixer/<source-id>/<original filename>` (with security
scope balanced around the copy), so the persisted URL stays playable after
relaunch and needs no bookmark. Reimporting the same source reuses its copy;
identical filenames from different sources stay distinct. `DiscourseAudioMixer`
then persists the copied URL through `audio_mixer_files`. Removing a row or
clearing the mixer deletes only copies under that directory, never the source
or a library file. The removed Local Library screen is not linked from the
Mixer. The legacy library context-menu action **Add to Audio Mixer** remains
available on upstream library surfaces, but is not required by this flow.

---

## 5. Repository conventions

### 5.1 Swift / Objective-C style

- Match surrounding code. The codebase is Swift 5 language mode with heavy
  Objective-C interoperability.
- Public Objective-C-visible Swift types use `@objc(VLCWhatever)` names and the
  `VLC` prefix, mirroring upstream.
- Lint is `Buildsystem/swiftlint.yml`; it enforces exactly one space around `=`,
  brace placement, `mark` format, etc. Keep new code lint-clean.
- Prefer `final class` for new leaf types; avoid force-unwraps in new code.
- New Swift files import only what they need. The bridging header
  (`Sources/Headers/VLC-iOS-Bridging-Header.h`) already exposes VLCKit,
  VLCMediaLibraryKit, XKKeychain and project headers.

### 5.2 Objective-C bridge

- The single bridging header is `Sources/Headers/VLC-iOS-Bridging-Header.h`
  (tvOS/watchOS have their own). Add new Objective-C headers there only when they
  must be visible to Swift.
- Objective-C nullability is `NS_ASSUME_NONNULL_BEGIN/END`; honour it.

### 5.3 Naming

- Upstream types keep their historical names (`VLCPlaybackService`,
  `MediaLibraryService`, …). **Fork-only** types use the `Discourse` prefix
  (`DiscourseAPIClient`, `DiscourseStore`, `DiscourseAudioMixer`, …).
- User-facing strings are new localisation keys in `Localizable.strings`.

### 5.4 Localisation & accessibility

- Every new user-facing string goes through `NSLocalizedString` and is added to
  `Resources/en.lproj/Localizable.strings` (base). Do not hard-code English in
  views.
- Every interactive control gets an `accessibilityLabel`; artwork gets a
  descriptive label. Support Dynamic Type (use semantic fonts / scalable metrics)
  so critical labels do not clip.

### 5.5 Asset catalogs & dependency policy

- New images go in `Resources/iOS/Images.xcassets` as new image sets. Theme colours
  are **code** (extend `ColorPalette` or add a fork palette in
  `Sources/UI Elements/PresentationTheme.swift`); the iOS catalog has no color sets
  and we do not add them.
- **Do not add a new third-party dependency** (Swift or ObjC) unless the existing
  stack cannot do the job. The discourse layer is built on `URLSession`,
  `Codable`, `UserDefaults`/Keychain and existing VLC types — no new pods/SPM.
- New launcher/onboarding/header artwork replaces upstream assets in place, or is
  added as new image sets referenced by the rebranded screens.

### 5.6 Registering new source files

`VLC.xcodeproj/project.pbxproj` uses classic `PBXGroup`s. New files must be added
to the correct group **and** the `VLC-iOS` target's Sources build phase, or the
build will fail to find the symbols. Use the helper script:

```bash
ruby Buildsystem/scripts/add_to_xcodeproj.rb \
  "Sources/Discourse" "DiscourseAPIClient.swift" "VLC-iOS"
```

After running it, verify with a build. Never hand-edit UUIDs in the pbxproj.

### 5.7 Commit style

- One coherent change per commit. Prefix with the area, e.g.
  `Discourse: add API client and models`, `Branding: rebrand app to Rajneesh
  Discourse`, `AGENTS: document playback architecture`.
- Commit messages describe *why*, not just *what*. Do not commit build artefacts,
  `DerivedData`, `Pods/`, `.env`, or secrets.

---

## 6. Product requirements

The authoritative product spec is the task brief. This section records the
concrete iOS decisions.

### 6.1 Navigation and screens

Exactly five bottom destinations, in order:

1. **Home** — vertical scroll, pull-to-refresh. Sections in order, each hidden when
   empty: Recently played (discourses), Recently played tracks (discourse + local
   history, deduped by media identity, hidden when playback history is off), Top
   discourses this week (`/stats?by=discourse&time=7_days`), Top tracks this week
   (`/stats?by=discourse_audio&time=7_days` — the deployed API rejects `by=audio`;
   `DiscourseStatsDimension.audio` maps to `discourse_audio`). Recently-played
   lists cap at **24**.
2. **Discourses** — remote catalogue with filters and paging.
3. **Search** — remote catalogue only.
4. **Playlists** — existing local playlist functionality, restyled.
5. **Audio Mixer** — second simultaneous local audio channel.

The old Browse tab, Videos tab, video browsing/settings, the music shuffle FAB,
and the file-menu items *Go to album / Go to artist / Create launcher shortcut /
Browse parent* are removed from the product surface. Incognito is removed from the
player overflow menu.

**Tab bar presentation.** Translucent floating capsule above the safe area,
opaque icons, theme-aware background; the mini player floats *above* the tab bar
(never clipped/overlapping) with safe-area padding.

**Implementation status (Phase 6).** All five destinations exist, each with an SF
Symbol tab item, a themed navigation bar and a Settings menu button. The
Discourses tab shows the live catalogue with 24-row paging, pull-to-refresh and language/sort filters (§4.9).
The tab bar itself still uses the upstream appearance and tint; the
floating-capsule styling, the discourse accent tint and the translucent
mini-player capsule are deferred to the styling pass (§10.18).

**Implementation status (Phase 8).** The Search tab is live: it queries both
`/discourses` and `/discourse-audios` from the remote catalogue, groups the
results into **Discourses** and **Tracks**, and pages both lists together
(§4.9). Tapping a track exercises the one-item queue plus continuation fetch
(§4.10). The Audio Mixer and the Playlists restyle remain for phases 13 and 14.

**Implementation status (Phase 9).** The Home tab is live with its four sections
(§4.9): recently played discourses and tracks from the local history stores, and
this week's top discourses and tracks from `DiscourseStatsCache`. Opening a
discourse records it in the history; the 60-second track qualification and stats
posting arrived with Phase 10.

**Implementation status (Phase 14).** *Recently played tracks* now merges the
discourse history with the device library's playback history (§4.9, §10.29):
library entries show `artist · duration`, carry no like/download controls and
play through the upstream library entry point. The Playlists tab keeps the
upstream grid and creation flow, now with the fork's accent tint and empty-state
copy that points at the local library instead of the removed Video/Audio tabs.

### 6.2 Discourse API integration

- Base URL `https://oshoapi-0i8tq.bunny.run/`, `x-api-key` on every request,
  JSON, snake_case fields. Models and routes are exactly as in the brief (§4 of the
  task) and are mirrored in `api/docs.md` / `api/types/discourse.type.ts`.
- Networking: 5 s connect / 15 s read timeouts; shared ~10 MB disk cache for GETs;
  GET responses cached 24 h **except `/likes` (never cached)**; on transport failure
  or 5xx serve stale cache if present, otherwise surface an error; force refresh
  sends `Cache-Control: no-cache`; a failed request never erases rendered content.
- URL resolution: absolute HTTPS used as-is; relative resolved against
  `https://osho.b-cdn.net/OSHO/`; non-HTTPS/unknown schemes rejected. Same rule for
  thumbnails.
- Error copy: generic `"Failed to communicate with the server."`; like failure
  `"Could not update your like. Tap the heart to try again."`.

### 6.3 Playback and queue behaviour

- Reuse `VLCPlaybackService` + `VLCMediaList`. Starting one track builds a queue
  that continues with the remaining tracks of that discourse; if only one track is
  known, the full discourse track list is fetched and appended **without
  interrupting playback**.
- Queue starting at index `n` continues at `n+1`.
- Discourse → `VLCMedia` mapping: URL = verified local download else resolved remote;
  title = track title; artist = `Osho`; album = discourse name; artwork =
  discourse thumbnail; track number = `track_number`; duration =
  `duration_seconds * 1000`; stable identifier carrying `discourseId` + `audioId`
  (survives queue serialisation).
- Position saved on pause/stop/next/media-change and every 30 s; restored when the
  item is created; completed at end; cleared on reset/replay-from-start.
- A play qualifies for stats/history only after **60 s of actual playback**
  (paused/buffering excluded); previous/next and queue transitions count.

**Implementation status (Phase 10).** The queue, the mapping, the continuation,
resume positions, 30 s progress saves (plus pause/stop/next/fail/background),
completion, replay-from-start clearing and the 60 s stats/history qualification are
live (§4.10). Downloads (the local-URL branch of the mapping) land in Phase 12.

### 6.4 Likes

Anonymous UUID identity; liked ID sets + last-fetch timestamp cached; refreshed
from `GET /likes` at most once every **7 days** and only on foreground/resume;
optimistic toggles; pending/settled IDs persisted; discourses and tracks
independent; counts formatted `999` / `1.2k` / `1m`; liked `#FF5269`, unliked
outline `#BEA8AA`; accessibility labels `"Like {title}. {n} likes"` /
`"Unlike {title}. {n} likes"`.

**Implementation status (Phase 11).** Live on every surface (§4.9): catalogue
cards, the Home card carousel, the detail header and rows, search/Home rows and
the full audio player. Counts are seeded from payloads, toggles are optimistic
with the store's rollback, and `.discourseLikesDidChange` reconfigures only the
visible surfaces. `GET /likes` is refreshed on launch and on every foreground
through the store's seven-day gate; pending toggles persist across relaunch.

### 6.5 Listening stats and history

Recently-played tracks (max 24, deduped by audio ID) and recently-played
discourses (max 24, recorded on open/play). `POST /stats` sent once per track per
24 h, deduped locally, marked sent only after a successful response. Weekly stats
cached **3 h**; force refresh replaces the cache. Playback-history setting gates
both history and stats.

**Implementation status (Phase 10).** Live: the 60 s qualification, the history
entries (track + discourse), the 24 h `POST /stats` dedupe and the
`playback_history` gate. Merging the device library's own playback history into
Home's *Recently played tracks* landed in Phase 14 (§10.29); the switch's
Settings row (Playback → **Playback history**, default on) landed in Phase 15
(§10.30).

### 6.6 Downloads

Background-capable `URLSession`; single-track and whole-discourse download;
per-track progress and per-discourse downloaded/active counts; states
`missing`/`downloading`/`downloaded`/`failed`; green downloaded icon; play from
local storage when verified (file exists and size > 0); else stream. Cancel stops
active downloads; remove deletes file + record; remove-all confirms
`"Remove all downloaded tracks from this discourse?"`; no orphan files; report
repeated failures once.

**Implementation status (Phase 12).** Live (§4.11): `DiscourseDownloadStore`
keeps `<audioID>.audio` files under Application Support with the two JSON maps,
verifies size before playback prefers a file, and prunes records or orphan files
on launch. `DiscourseDownloadManager` drives a background `URLSession` (three
tracks at a time, pending queue, relaunch reattachment) for single tracks and
whole discourses, broadcasting `.discourseDownloadsDidChange`. Rows carry the
arrow/ring/tick/failure control, the detail nav-bar menu downloads/cancels/removes
a discourse, and catalogue/Home cards show the `3/11` badge. Verified live in the
simulator: a 1.5 h track downloaded to `Application Support/Discourses/<id>.audio`,
the row turned green, the card read `1/11`, and **Remove all downloads** emptied
the directory. Playing a verified download is covered by unit tests rather than a
device check (§8).

### 6.7 Audio Mixer

A **second** `VLCMediaPlayer` playing one local file simultaneously with the main
player. Only files explicitly added through **Add audio file** (or the legacy
library **Add to Audio Mixer** action) appear. Order
persisted; add/remove/reorder/clear. Defaults: enabled **false**, loop **true**,
volume **50** (clamped 1…100). Follows the main player: start/resume ~250 ms after
main `Playing` (audio only), pause on main pause, stop on main stop/end, stop on
video. On mixer `EndReached`, loop restarts if enabled. Loop toggle reloads media.
Fade in ~200 ms (5×40 ms), fade out ~220 ms. Mixer volume **never** resets to 100 %
or to main volume. One `AVAudioSession` for playback; handle interruptions, route
changes and media-services resets by pausing both and restoring mixer state.

**Implementation status (Phase 13).** Live (§4.12): `DiscourseAudioMixer` owns a
second `VLCMediaPlayer` gated by `audio_mixer_enabled`; the Audio Mixer tab shows
the panel (on switch, now playing with play/pause, loop, 1…100 volume) and the
ordered track list (select, long-press drag reorder, swipe delete, **Clear all**
with confirmation). The **+** button and empty-state **Add audio file** action
open the system Files picker; selected files are copied into app-owned storage
(§4.12) and remain playable after relaunch. The removed Local Library screen is
not linked from the Mixer. The mixer
joins the main player 250 ms after it starts (audio only), pauses/resumes with it,
stops on stop/fail and on video, loops when asked, reloads on a loop change, fades
in/out and keeps its own volume. Verified live in the simulator: a generated local
track joined a playing discourse, paused and resumed with the mini player's
play/pause, and **Clear all** emptied the list.

### 6.8 Design system and theme tokens

Dark burgundy / near-black palette with warm surfaces, rounded cards and red
accents. Dark is the default; a light palette with equivalent semantics is
provided. Token values are exactly those in the brief (Accent, App background,
Detail background, Surface, Border, Primary/Secondary text, Divider, Liked/Unliked
heart, Downloaded; plus Audio Mixer, Mini player palettes). Corner radius: 8 pt
thumbnails, 8–16 pt cards, 16 pt mixer panel. The Home carousel keeps the
brief's 160×160 artwork tiles; the catalogue renders the same card as a
full-width list row (88 pt artwork) with title ≤ 2 lines, language, track count,
download badge and like control. Track rows: 48×48
thumbnail, title ≤ 2 lines, metadata, like, played/download indicators, overflow.
Artwork aspect-fill + rounded corners. Controls are theme-aware — never hard-code
black text on dark surfaces.

**iOS implementation of the palette:** extend the existing `PresentationTheme`
model rather than introducing a second theme system. Fork semantic colours are
added as a `DiscourseColors` struct resolved from `PresentationTheme.current`
(so light/dark switches with the existing infrastructure and posts
`.VLCThemeDidChangeNotification`). Dark is registered as the default for first
launch by defaulting `kVLCSettingAppTheme` to dark for this fork.

### 6.9 Branding and About

App display name, onboarding, About, permission prompts, empty states,
notifications and widgets say **Rajneesh Discourse**. Launcher icon, onboarding
artwork and header/logo are Rajneesh Discourse assets (header mark 8 pt rounded).
About text: *"Rajneesh Discourse is a local media player distributed by Sandalbar
Enterprises, Inc. It is built from open-source software; upstream authors and
licenses are listed below."* Website/help links point to
<https://rajneeshdiscourse.com>. Upstream feedback/bug-tracker/source links are
removed. Upstream licence acknowledgements stay.

---

## 7. Local persistence contract

All new keys use the `osho_api_*` / `audio_mixer_*` names from the brief so
behaviour is comparable with Android. **Owner** is the single type allowed to read
or write the key.

| Key / store | Type | Owner | Notes |
|---|---|---|---|
| `osho_api_user_id` | `String` (UUID) | `DiscourseIdentity` | Mirrored in Keychain (durable) + UserDefaults (fast). |
| Keychain service `online.sandalbar.rajneesh-discourse.identity` (service id) | generic password | `DiscourseIdentity` | Durable copy of the UUID. |
| `osho_api_liked_discourses` | `[String]` | `DiscourseLikesStore` | Liked discourse IDs. |
| `osho_api_liked_audios` | `[String]` | `DiscourseLikesStore` | Liked track IDs. |
| `osho_api_likes_fetched_at` | `Double` (epoch seconds) | `DiscourseLikesStore` | 7-day TTL gate. |
| `osho_api_likes_pending` | JSON `[String: Bool]` (`"discourse:<id>"` / `"audio:<id>"`) | `DiscourseLikesStore` | In-flight toggles, restored on launch. |
| `osho_api_recently_played_discourses` | JSON `[Discourse]` | `DiscourseHistoryStore` | Max 24. |
| `osho_api_recently_played_audios` | JSON `[DiscourseAudio]` | `DiscourseHistoryStore` | Max 24. |
| `osho_api_catalogue_language` | `String?` | `DiscourseCatalogueFilterStore` | Last language filter. |
| `osho_api_catalogue_sort` | `String?` | `DiscourseCatalogueFilterStore` | Last sort filter. |
| `osho_api_stats_discourses` (+ `.time`) | JSON `[Discourse]` + `Double` | `DiscourseStatsCache` | 3 h TTL, weekly window only. |
| `osho_api_stats_audios` (+ `.time`) | JSON `[DiscourseAudio]` + `Double` | `DiscourseStatsCache` | 3 h TTL, weekly window only. |
| `osho_api_discourse_playback_position.<audioId>` | `Double` (ms) | `DiscoursePlaybackStore` | Per-track resume. |
| `osho_api_discourse_completed_audios` | `[String]` | `DiscoursePlaybackStore` | Tracks played to the end; cleared on replay-from-start. |
| `osho_api_discourse_track_info` | JSON `[audioId: {discourseID, durationMilliseconds}]` | `DiscoursePlaybackStore` | Track index for progress rings. |
| `osho_api_discourse_played_audios` | `[String]` | `DiscoursePlaybackStore` | Manually marked played. |
| `osho_api_stats_sent` | JSON `[String: Double]` (audioId → epoch) | `DiscourseStatsStore` | Local 24 h stats dedupe (Android used a separate `osho_api_stats` prefs file; iOS mirrors it in UserDefaults with timestamps). |
| `osho_api_discourse_media_identity` | JSON `[audioURL: {discourseID, audioID, recordedAt}]` | `DiscourseMediaIdentityStore` | Bounded (512) URL → identity index; lets a queue restored from the last-played playlist keep its discourse/track attribution. |
| `osho_api_discourse_downloads` | JSON `[audioId: filename]` | `DiscourseDownloadStore` | Local file records. |
| `osho_api_discourse_download_discourses` | JSON `[audioId: discourseId]` | `DiscourseDownloadStore` | Reverse index. |
| `playback_history` | `Bool` (absent = `true`) | `DiscoursePlaybackSettings` | Fork playback-history switch, same key as the Android reference. Not yet exposed in Settings (§10.30). |
| `audio_mixer_files` | `[String]` (URL strings) | `DiscourseAudioMixer` | Ordered membership; normally app-owned import copies, or legacy library URLs added through the context action. |
| `audio_mixer_selected` | `String?` | `DiscourseAudioMixer` | Selected track. |
| `audio_mixer_enabled` | `Bool` (default `false`) | `DiscourseAudioMixer` | Persisted. |
| `audio_mixer_loop` | `Bool` (default `true`) | `DiscourseAudioMixer` | Persisted. |
| `audio_mixer_volume` | `Int` (default `50`, 1…100) | `DiscourseAudioMixer` | Persisted; never reset by main player. |
| Mixer imports | files under Application Support `AudioMixer/<source-id>/` | `DiscourseMixerFileImporter` | Document-picker copies; original filename preserved, removed with the mixer item. |
| Downloaded files | files under Application Support `Discourses/` | `DiscourseDownloadStore` | Named `<audioId>.audio`. |
| API responses | `Caches/DiscourseAPI/*.json` (≈10 MB) | `DiscourseAPICache` | 24 h freshness, `/likes` excluded, oldest evicted first. |

**Rules.** Decode defensively (a corrupt JSON value is treated as empty, never
crash). Writes are synchronous to `UserDefaults` on the main actor and/or
serialised through each store's queue. Never store the API key, the user UUID in
logs, or tokens anywhere world-readable.

`DiscourseTrackRegistry` is the one exception to the table: it is an in-memory,
bounded (256) cache of the `DiscourseAudio`/`Discourse` payloads that built the
current queue, used by the playback tracker to record history after the 60 s
qualification. It is never persisted; a queue restored after a relaunch has no
payload and the tracker fetches it once from `/discourse-audios`.

---

## 8. Testing and verification

Run everything listed in §3.5 plus the manual matrix:

| Area | Verify |
|---|---|
| Build | Clean build via the documented command; no new correctness warnings. |
| Regression | VLC local playback, playlists, background audio, lock-screen controls still work. |
| Navigation | Exactly 5 tabs; no Browse/Videos; branding correct; site link `rajneeshdiscourse.com`; dark on first launch; light usable. |
| Catalogue | Load, paginate (16/page), refresh, search, language filter, `most_liked` sort; detail loads all tracks; Play all / track tap queue correctly; queue continues past a single fetched track. |
| Home | Four sections in order, each hidden while empty; opening a discourse adds it to *Recently played*; pull-to-refresh forces the weekly lists; empty, error and history-only states; recently played tracks hidden while playback history is off. |
| Likes | Independent discourse/track likes; optimistic counts reconcile; persist across relaunch and offline failures; 7-day refresh TTL; correct failure message + revert. |
| Stats/history | 60 s qualification; pause/buffering excluded; next/previous transitions; 24 h dedupe; recently-played cap 24; weekly cache 3 h; history setting gates everything. |
| Downloads | One/all, progress, cancel, remove, remove-all; offline playback; icon/counts; missing file → stream; survive backgrounding. |
| Audio Mixer | Add audio through **+**/the empty-state action and the Files picker (copied into the app); select/drag-reorder/swipe-remove/clear; removal deletes only imported copies; start/pause/stop follows main; stops on video; loop default on and restarts; volume default 50 and persistent; enable/loop/volume persist; no click on fade; survives interruption/route change/relaunch; no crash when the selected file is deleted. |
| A11y/l10n | VoiceOver identifies artwork, like buttons, toggles, sliders, rows; Dynamic Type does not clip; all new strings localisable. |

Offline, background, interruption (phone call/Siri), route change (headphones),
and media-services-reset scenarios are manual device checks. Automated coverage
grows in `Buildsystem/Testing/Unit/` (API decoding, URL resolution, like-count
formatting, 60 s/stats dedupe, progress maths, mixer state machine).

Already covered by `DiscourseAPITests` (12 cases, run through `VLC-iOS-Tests`):
payload decoding for catalogue/tracks/stats/likes (including nulls and missing
fields), HTTPS-only URL resolution and CDN escaping, cache freshness/eviction,
error classification and the `userMessage` copy, keychain UUID validation.
`DiscourseFormattingTests` (6 cases) pins the compact count shapes used by the
catalogue cards and, later, the like controls. `DiscoursePlaybackTests` (13
cases) covers durations, the URL → identity index (round-trip, replacement,
pruning, persistence, corrupt storage), queue construction (skipped tracks and
start index) and the track → media mapping (title/artist/album/track number/
artwork/duration, identity extras and the URL fallback). `DiscourseSearchTests`
(5 cases) pins the two-section accumulator: both lists appended together, ids
deduped across pages, paging following the deeper endpoint, empty results and
reset. `DiscourseHomeTests` (6 cases) pins the Home section assembly: product
order, empty sections dropped, recently played tracks hidden while playback
history is off, id dedupe and the 24-entry cap. `DiscoursePlaybackProgressTests`
(13 cases) pins the playback rules without a player: 60 s qualification, paused
and buffering time excluded, seeks and the resume offset ignored, a save every
30 s, flush on pause/stop, completion and no double completion, replay-from-start
re-arming, the resume fraction (minimum, tail margin, completion, start
position), a learned duration, plus the bounded payload registry.
`DiscourseStoresTests` also covers the like-control state (the payload count
until the store knows one, the stored count winning, the liked sets feeding
`isLiked`), so the unit suite pins the whole likes path except the network.
`DiscourseDownloadTests` (10 cases) pins the download store without a network:
records and verified files, persistence across instances, empty files not
counting as downloads, corrupt records treated as empty, path sanitisation,
single/whole-discourse/all removal, pruning of records whose file vanished and
deletion of orphan files. Two more playback cases pin the mapping preference (a
verified download becomes the media URL; a deleted file streams again), so the
unit suite covers the whole download path except the transfer itself.
`DiscourseMixerTests` (18 cases) pins the Audio Mixer without a player: the
documented defaults (off, looping, volume 50), ordered membership with duplicate
and non-file rejection, selection and reorder persistence, the selection falling
back after a removal, clear, switch persistence, 1…100 volume clamping and
file-name titles, plus document-picker imports (copy and relaunch persistence,
same-source dedupe, same-name/different-source separation, unreadable and empty
file failures, and deletion of app-owned copies only). Four Home cases pin the
merge: library entries follow the discourse history, both sides hide while
history is off, library entries dedupe by file URL, and the merged list caps at
24. **132 unit tests, 0 failures.**
The catalogue's paging and filter flow, the card → detail → back navigation, the
Search tab (both sections, discourse → detail, track → full player), Home
(recently played → detail), the detail header's like → unlike → like round trip
the download → menu → remove-all round trip and the Audio Mixer panel plus its
file-picker flow are covered by `VLCTestMenu` (15 tests) plus the manual matrix
above. The like test waits for each request to settle before the next tap because
the store ignores a second tap while one is in flight, and it restores the
unliked state. The download test fetches one real track (~40 MB), asserts the
green state, then removes it through the discourse menu so the simulator keeps no
files; when the CDN has not delivered it within 150 s the test cancels and skips
instead of failing the suite (the store and the playback preference are covered
by unit tests and the manual matrix). `DiscourseLaunchScreenTests` (1 case)
checks the launch storyboard still resolves its branded image. The mixer test
clears any tracks left by earlier runs before asserting the empty state, so it
is order-independent.
`testPlaybackHistorySettingToggles` opens Settings, flips the switch, waits for
each value and restores the original state, so the 16 UI tests leave the app as
they found it.

---

## 9. Current implementation status

Google Drive and Google Sign-In are removed from the app: no cloud-list entry,
Drive favourite routing, OAuth URL handler, URL scheme, or Google pods remain.
Upstream Google Drive source files and shortcut tests remain as unbuilt references.
OneDrive and its ADAL authentication dependency are also removed, along with the
last `UIWebView` references (ITMS-90809). AlarmKit, Face ID biometrics,
photo-library saving and iCloud Documents were removed in the follow-up
permission cleanup, leaving Local Network as the only runtime privacy prompt.
Verified: `VLC-iOS-no-watch` and `VLC-iOS` simulator builds pass with no
`UIWebView`, ADAL or OneDrive artifacts in the built app; the focused
`VLC-iOSTests/URLHandlerTests` suite passes both tests, including absence of
Google OAuth handler and URL-scheme registration.


> Updated in the same commit as the change. Legend: **Done**, **Partial**, **Missing**.

### Phase 1 — repository discovery
- **Done.** Architecture map above (this file). No code changes.

### Phase 2 — branding, theme, remove Browse/Videos — **Done (text/theme) · artwork pending**
- **Done.** App `CFBundleDisplayName`/`CFBundleName` = *Rajneesh Discourse*;
  About page rebranded (Sandalbar paragraph, `rajneeshdiscourse.com` website/help
  link, upstream source and feedback links removed, licence acknowledgements
  kept); menu = *About Rajneesh Discourse* (the *Help & Website* item added here
  was removed in the later header polish, so the menu is now About + Settings);
  English base strings updated; dark registered as
  the first-launch default;
  `DiscourseColors` added with the brief's exact light/dark tokens (catalogue,
  track, playlist, audio-mixer and mini-player palettes); Videos and Browse tabs
  and the video quick action removed; Media Library shortcut renamed accordingly.
- **Partial — artwork.** The onboarding illustrations and the VLC-cone
  placeholders (passcode, donation screens) are still upstream assets; see
  §10.9. The launcher icon, launch screen, header button, About icon and
  empty-library / playlists artwork are branded.

### Phase 3 — API client, models, identity, cache — **Done**
- **Done.** `Sources/Discourse/API/` (§4.7): Codable models exactly matching
  `api/types/discourse.type.ts`, defensive decoding; `DiscourseAPIClient` with
  `x-api-key`, 15 s read / 30 s resource timeouts, `Cache-Control: no-cache` on
  force refresh, 24 h disk cache with stale-on-failure fallback, `/likes` never
  cached, cancellation-safe; `DiscourseURLResolver` (HTTPS only, relative paths
  against `https://osho.b-cdn.net/OSHO/`); `DiscourseIdentity` (keychain +
  UserDefaults UUID); `DiscourseAPIError` with the spec's generic copy;
  `DiscourseDiagnostics` logging with no secrets.
- **Done — build wiring.** *Generate Discourse API Secrets* run-script phase on
  both iOS app targets writes `DiscourseSecrets.h` into the shared derived
  sources; the iOS bridging header imports it; `HEADER_SEARCH_PATHS` updated on
  `VLC-iOS`, `VLC-iOS-no-watch` and `VLC-iOSTests`.
- **Done — tests.** `Buildsystem/Testing/Unit/DiscourseAPITests.swift`
  (12 cases) registered in `VLC-iOSTests`; the whole suite runs green.
- **Verified live** against the backend in the iPhone 16 Pro simulator: catalogue
  page (24 rows, 349 total), all tracks of a discourse, cached re-read (0 ms),
  forced refresh (network), `/likes`, `/stats`; the anonymous UUID survived a
  relaunch.

### Phase 4 — persistent stores — **Done**
- **Done.** `Sources/Discourse/Stores/` (§4.8): `DiscourseSettings` (typed
  `UserDefaults` + defensive JSON), `DiscourseNotifications` (three change
  names), `DiscourseLikesStore` (liked sets, optimistic toggle + rollback, pending
  map, 7-day `GET /likes` gate, counts from payloads), `DiscourseHistoryStore`
  (recently played, max 24, deduped), `DiscourseStatsStore` (24 h `/stats`
  dedupe, marked only after success), `DiscourseStatsCache` (weekly top lists,
  3 h TTL, stale-on-failure, other windows uncached),
  `DiscoursePlaybackStore` (resume positions, completion, progress fractions,
  played flag, track index) and `DiscourseCatalogueFilterStore`.
- **Done — tests.** `Buildsystem/Testing/Unit/DiscourseStoresTests.swift`
  (20 cases) registered in `VLC-iOSTests`. Verified command in §3.5:
  **39 tests, 0 failures** (12 API + 20 store + 7 upstream).
- **Wiring.** Nothing observes the stores yet; Phase 5 onward consumes them.

### Phase 5 — five-tab navigation shell — **Done**
- **Done.** `TabBarCoordinator` now builds exactly five destinations — Home,
  Discourses, Search, Playlists, Audio Mixer — with SF Symbol tab items,
  `VLCAccessibilityIdentifier` identifiers, per-tab nav-bar identifiers, index
  persistence (0…4) and iPad sidebar support without the audio sub-page
  flattening. Videos, Browse, On Air and the separate Audio tab are gone from the
  surface; their classes stay for upstream sync.
- **Done — fork screens.** `Sources/Discourse/UI/`: `DiscourseScreenViewController`
  (themed background, Settings menu button, theme refresh, large titles),
  `DiscourseEmptyStateView` (symbol, heading, copy, optional action, Dynamic Type,
  `DiscourseColors`) plus `DiscourseHomeViewController`,
  `DiscourseCatalogueViewController`, `DiscourseSearchViewController` and
  `DiscourseAudioMixerViewController`. Home, Search and the Audio Mixer show their
  legitimate empty state until their own phase; no fake interactions. (The
  catalogue left the shared base in Phase 6 when it gained its grid, which a
  later polish pass turned into a one-column list.)
- **Done — local library.** The device audio browser (upstream
  `AudioViewController`) is pushed from the Discourses empty state, so local
  playback, playlists and background audio remain reachable; the last-played
  shortcut and album deep links go through the same path.
- **Done — tests.** `VLCTestMenu` rewritten for the shell: 7 UI tests (one per tab,
  local library reachable, About via Settings) and 39 unit tests, all green on the
  iPhone 16 Pro simulator.
- **Pending.** The floating-capsule tab bar and discourse accent tint (§10.18).

### Phase 6 — catalogue, filters and paging — **Done**
- **Done — catalogue.** `DiscourseCatalogueViewController` (§4.9) renders the
  remote catalogue as a full-width list of `DiscourseCardCell`s (one column,
  artwork left, content right; the two-column grid of this phase was replaced
  during the UI polish pass): artwork through
  `VLCNetworkImageView`/`VLCThumbnailsCache`, title (two lines), language and
  track/like counts (`DiscourseCountFormatter`: 999 / 1.2k / 12k / 1m), with
  singular forms for one track and one like.
- **Done — loading.** First page from the 24 h cache or the network, pull-to-
  refresh as a force refresh, paging on scroll (`page < meta.total_pages`, deduped
  by id and appended with `insertItems`), and a request token that drops stale
  answers when a filter changes. Failure with rows already rendered keeps them.
- **Done — filters.** A bar-button `UIMenu` for language (all/English/Hindi) and
  sort (default/most liked), persisted in `DiscourseCatalogueFilterStore`, with
  *Clear filters* while a filter is active. The chosen language also drives
  `DiscourseLanguage` display names on the cards.
- **Local library.** The earlier Discourse/Local switch was removed. Local media
  shortcuts push the Songs and Folders pages above the catalogue; the Mixer
  imports files directly through the document picker and never links to this
  screen. Its empty state offers the external folder picker and says **No files
  found** when an external folder is accessible.
- **Done — tests.** `DiscourseFormattingTests` (6 cases) plus 39 existing =
  **45 unit tests, 0 failures**; `VLCTestMenu` then had 8 UI tests (local library
  reachability, filter menu apply/clear) — all green on the iPhone 16 Pro
  simulator. The mixer's local-library action was later replaced by the file
  picker (§9, post-phase polish). Paging verified manually to page 3 (page-3 rows visible after
  scrolling; the grid never duplicates rows).
- **Deferred.** Card like control (landed in Phase 11) and download row
  (Phase 12); the footer had no reserved space for them, so neither shifted the
  grid (§10.20).

### Phase 7 — discourse detail, track actions, queue continuation — **Done**
- **Done — detail.** `DiscourseDetailViewController` (§4.9) pushes from a
  catalogue card: artwork + title + `language · tracks · likes` + filled **Play
  all**, a sorted track list (position/playing glyph, title ≤2 lines, duration),
  tap-to-play from that index, and a long-press menu with **Play** / **Play next**
  / **Add to queue**. Spinner, empty and failure states, pull-to-refresh as a
  force refresh, and a request token for stale answers.
- **Done — playback bridge.** `Sources/Discourse/Playback/` (§4.10):
  `DiscourseMediaFactory` maps a track to `VLCMedia` (title, artist `Osho`, album,
  artwork, track number, duration, identity extras) and builds the queue;
  `DiscoursePlayback` starts it through
  `PlaybackService.playMediaList(_:firstIndex:subtitlesFilePath:)`, supports
  play next / add to queue, and extends a one-item queue with the remaining
  tracks of the discourse after fetching them, without interrupting playback.
- **Done — identity.** `DiscourseMediaIdentityStore` (§7) keeps a bounded
  URL → `{discourseID, audioID}` index so a queue restored from the last-played
  playlist keeps its attribution; the media also carries `rd.discourseID` /
  `rd.audioID` meta extras for the same lookup in memory.
- **Done — mini player inset.** The detail table and the catalogue list add
  `AudioMiniPlayer.height` to their bottom inset while the mini player is
  visible, so the last row/cards scroll clear of it.
- **Done — tests.** `Buildsystem/Testing/Unit/DiscoursePlaybackTests.swift`
  (13 cases: durations, identity store round-trip/replacement/pruning/persistence/
  corrupt data, queue skipping and start index, metadata mapping, extras and the
  URL fallback) plus the existing 45 = **58 unit tests, 0 failures**;
  `VLCTestMenu` adds `testCatalogueOpensDiscourseDetail` = **9 UI tests, 0
  failures**, all on the iPhone 16 Pro simulator.
- **Verified live.** A catalogue card opens the detail (11 tracks, 1:37:49 each);
  **Play all** starts track 01 with the full player showing title *A Bird on the
  Wing 01*, artist *Osho*, album *A Bird on the Wing* and the discourse artwork;
  closing it leaves the mini player with the same metadata and marks row 01 as
  playing; durations and the like count match the payload.
- **Deferred.** Progress rings/played indicators, resume positions and the 60 s
  qualification (Phase 10), like controls (landed in Phase 11) and download rows
  (Phase 12). Track rows reserved no space for them.

### Phase 8 — search across discourses and tracks — **Done**
- **Done — search screen.** `DiscourseSearchViewController` (§4.9) replaces the
  placeholder: a navigation-bar `UISearchController`, a 350 ms debounce, an
  immediate query on the keyboard's search key, a request token that drops stale
  answers, and idle / loading / results / no-matches / failure states through
  `DiscourseEmptyStateView`. Pull-to-refresh forces a network read.
- **Done — both result types.** Each query fetches `/discourses?search=` and
  `/discourse-audios?search=` concurrently and renders **Discourses** then
  **Tracks** sections (hidden while empty); paging loads the same page number from
  both endpoints until the deeper one is exhausted. `DiscourseSearchResults`
  dedupes ids across pages; `DiscourseSearchCell` renders the discourse summary or
  the track's discourse name + duration with the same row layout.
- **Done — actions.** A discourse result pushes `DiscourseDetailViewController`;
  a track result starts through `DiscoursePlayback.play(track:discourse:)` (the
  one-item queue that appends the rest of its discourse without interrupting), and
  the results table marks the playing row and grows its mini-player inset.
- **Done — tests.** `Buildsystem/Testing/Unit/DiscourseSearchTests.swift`
  (5 cases: both sections appended, dedupe across pages, shorter endpoint stops
  paging, empty results, reset) plus the existing 58 = **63 unit tests, 0
  failures**. `VLCTestMenu` adds `testSearchFindsDiscoursesAndTracks` (sections,
  rows, discourse → detail) and `testSearchTrackStartsPlayback` (track → full
  player), so the UI suite is **11 tests, 0 failures** on the iPhone 16 Pro
  simulator.
- **Verified live.** `search=dhyan` returns 10 tracks of *Dhyan Darshan* plus the
  matching discourses; the sections and rows render, the discourse opens its
  detail, and tapping a track starts playback with the full player.
- **Deferred.** Likes on result rows (landed in Phase 11) and download
  indicators (Phase 12); search history/recent queries are not part of the
  brief.

### Phase 9 — Home sections + weekly stats — **Done**
- **Done — Home screen.** `DiscourseHomeViewController` (§4.9) replaces the
  placeholder with a compositional collection view of four sections in product
  order, each dropped while empty: **Recently played** (discourse cards),
  **Recently played tracks** (rows), **Top discourses this week** and **Top
  tracks this week** (`/stats?by=discourse|discourse_audio&time=7_days` through
  `DiscourseStatsCache`). Discourses scroll as a 160 pt card carousel; tracks are
  full-width rows.
- **Done — shared row.** `DiscourseRowView` carries the artwork/title/summary/
  duration layout; `DiscourseSearchCell` (table) and `DiscourseHomeTrackCell`
  (collection) are thin hosts, so search and Home rows cannot drift apart.
- **Done — assembly.** `DiscourseHomeContent` owns the ordering, id dedupe, the
  24-entry cap on the recently-played lists and the history gating, and is
  covered without UIKit.
- **Done — history.** Opening `DiscourseDetailViewController` records the
  discourse in `DiscourseHistoryStore` (newest first) when
  `DiscoursePlaybackSettings.isHistoryEnabled`. Home rebuilds the history
  sections on `viewWillAppear` and on `.discourseHistoryDidChange`.
- **Done — states.** Spinner while nothing is available and the first stats
  request runs, the Home empty state when every section is empty, *Could not load
  the top lists* with *Try again* when stats fail and there is no history, and
  history-only content (no error screen) when stats fail but history exists.
  Pull-to-refresh forces both weekly lists.
- **Done — stats refresh fix.** `DiscourseStatsService` gained a `forceRefresh:`
  parameter; `DiscourseStatsCache` forces the network when its 3 h TTL expires
  instead of accepting the API layer's 24 h copy (§4.8).
- **Done — tests.** `Buildsystem/Testing/Unit/DiscourseHomeTests.swift` (6
  cases: empty payloads, product order, empty sections dropped, history gating,
  id dedupe, 24-entry cap) plus the existing 63 = **69 unit tests, 0 failures**.
  `VLCTestMenu` adds `testHomeShowsRecentlyPlayedDiscourse` (open a discourse,
  find it under *Recently played*, open it again), so the UI suite is **12
  tests, 0 failures** on the iPhone 16 Pro simulator.
- **Verified live.** The Home tab shows the discourse opened from the catalogue
  under *Recently played*, 3 live top discourses and 8 live top tracks; the
  carousel and the rows render with the same card/row content as the catalogue
  and search, and the card opens the detail.
- **Deferred.** Track history recording (60-second qualification), `POST /stats`
  and merging the device library's playback history into *Recently played tracks*
  are Phase 10; likes on Home cards/rows landed in Phase 11, downloads are
  Phase 12; the Settings toggle for `playback_history` is Phase 15 (§10.29–30).

### Phase 10 — playback integration: resume, progress, 60 s stats/history — **Done**
- **Done — rules.** `Sources/Discourse/Playback/DiscoursePlaybackProgress.swift`
  (§4.10) holds the 60 s qualification, the 30 s save cadence, the completion
  tolerance, the seek cap and the replay-from-start re-arm with no player
  dependency. Accumulation uses position deltas only while `isPlaying`, so pauses,
  buffering and seeks never count. `DiscoursePlaybackResume` turns a stored
  position into the fraction `VLCPlaybackService.startPosition` expects.
- **Done — tracker.** `DiscoursePlaybackTracker` observes
  `Playback{DidStart,DidPause,WillStop,DidStop,DidFail,DidMoveOnToNextItem,
  PositionUpdated}` plus resign-active/enter-background, writes resume points and
  completion to `DiscoursePlaybackStore`, and on qualification records the track
  (and its discourse) in `DiscourseHistoryStore` and posts `POST /stats` once per
  24 h through `DiscourseStatsStore`. Both are gated by
  `DiscoursePlaybackSettings.isHistoryEnabled`. Started from
  `TabBarCoordinator.setup()`.
- **Done — resume.** `DiscoursePlayback.play(tracks:discourse:startingAt:)` sets
  `startPosition` for the item it starts at (≥1 s, not into the last 5 s, ≤0.98,
  never for a completed track) before `playMediaList`; later items start at 0.
- **Done — payload registry.** `DiscoursePlayback` registers queued tracks and
  discourses in the bounded in-memory `DiscourseTrackRegistry` and registers
  durations in `DiscoursePlaybackStore`. A restored queue with no payload is
  fetched once from `/discourse-audios` when a play qualifies.
- **Done — rows.** `DiscourseTrackCell` now leads with
  `DiscourseTrackProgressView`: the track number in a progress ring, the speaker
  while playing, a checkmark when finished; `DiscourseDetailViewController`
  registers durations on load and refreshes only the affected visible row on
  `.discoursePlaybackProgressDidChange`. New string `DISCOURSE_TRACK_PLAYED`.
- **Done — tests.** `DiscoursePlaybackProgressTests` (13 cases: 60 s threshold,
  paused/buffering excluded, seek and resume offsets ignored, 30 s saves, flush,
  completion/no double completion, replay re-arm, the resume fraction, learned
  duration, registry eviction/replacement) plus the existing 69 = **82 unit
  tests, 0 failures**. UI suite unchanged at **12 tests, 0 failures**.
- **Verified live.** A UI run played a discourse for 70 s, terminated and
  relaunched: Home showed *Recently played tracks*, and the app defaults held
  `osho_api_discourse_playback_position.<audioId>` ≈ 60.9 s,
  `osho_api_recently_played_audios`, `osho_api_recently_played_discourses` and
  `osho_api_stats_sent` — the qualification, the resume save, the history and the
  `/stats` report all fired.
- **Deferred.** Merging the device library's playback history into Home's
  *Recently played tracks* moved to Phase 14 (§10.29); likes on rows landed in
  Phase 11, downloads are Phase 12, the `playback_history` Settings row is
  Phase 15 (§10.30).

### Phase 11 — likes UI across cards, detail, rows and the player — **Done**
- **Done — one control.** `DiscourseLikeControl` (§4.9) renders the heart and the
  compact count from `DiscourseLikeState.resolve`: a filled heart in the liked
  colour, the spec's accessibility labels and an *Updating* value while a request
  is in flight, a 44 pt touch target around the 18 pt glyph, and `.surface` /
  `.player` colour variants.
- **Done — one action.** `DiscourseLikeActions` performs the store toggle and
  presents `DiscourseErrorCopy.likeFailure` in an alert, so every surface reuses
  the same optimistic/rollback behaviour.
- **Done — surfaces.** Catalogue and Home carousel cards (footer, replacing the
  likes text in the metadata line with the heart's own count), the detail header
  (next to **Play all**) and detail rows, search and Home track rows (trailing;
  the duration moved into the metadata line), and the full audio player's
  navigation bar (before more-options, hidden unless the playing media has a
  discourse payload).
- **Done — live counts.** Every list seeds `DiscourseLikesStore.updateCount` from
  its payload, and `.discourseLikesDidChange` reconfigures only the visible
  cards/rows (the catalogue list, the detail header plus visible rows, the search
  rows, the Home cells) so taps settle without a reload or a scroll jump.
- **Done — refresh.** `TabBarCoordinator` refreshes `GET /likes` on launch and on
  every foreground; the store's seven-day window decides whether that is a
  network call.
- **Done — accessibility.** Cards and rows became **containers** so the heart is
  focusable: a transparent `DiscourseAccessibilityButton` carries the row's label
  and opens the discourse/starts the track, and the like control is a separate
  button with the spec's like/unlike labels. The cell itself keeps its
  `accessibilityIdentifier` (and the card keeps a label) so the existing UI tests
  still find rows.
- **Done — tests.** 3 new unit cases in `DiscourseStoresTests` (**85 unit tests,
  0 failures**) and one new UI test, `testDiscourseLikeTogglesFromTheDetailHeader`
  (like → unlike → like against the live API, restoring the unliked state):
  **13 UI tests, 0 failures** on the iPhone 16 Pro simulator.
- **Verified live.** The catalogue cards show `11 tracks · ♥ 1`, the detail
  header sits the heart next to **Play all**, track rows end with the duration
  and the heart, Home rows read `A Bird on the Wing · 1:37:49` with the heart at
  the trailing edge, and the full player shows the heart before more-options.
  Screenshots were captured from the UI test run.
- **Deferred.** The mini player has no like control (it shows metadata only);
  the row/card download indicators landed in Phase 12.

### Phase 12 — downloads — **Done**
- **Done — store.** `DiscourseDownloadStore` (§4.11) owns the
  `Application Support/Discourses/<audioID>.audio` files and the two JSON maps
  (`osho_api_discourse_downloads`, `osho_api_discourse_download_discourses`).
  `localURL(for:)` verifies the file exists and is not empty, so playback streams
  when a file was deleted or truncated. Launch prunes records whose file vanished
  and deletes files no record mentions; filenames are sanitised.
- **Done — manager.** `DiscourseDownloadManager` runs a background `URLSession`
  (three concurrent, pending queue, `taskDescription` = `audioID|discourseID` for
  relaunch reattachment), reports progress at most every 2% on the main thread
  and exposes `missing`/`downloading(progress)`/`downloaded`/`failed`. Single
  track, whole discourse, cancel, remove, remove-all and per-discourse active
  counts are all supported. `VLCAppDelegate` forwards the background-session
  event and the manager releases the system's completion handler.
- **Done — UI.** `DiscourseDownloadControl` on every track row (detail, search,
  Home) and `DiscourseDownloadActions` for the shared tap/menu/confirmation
  semantics. The detail nav-bar menu offers **Download all**, **Cancel
  downloads** and **Remove all downloads** (confirming with the brief's copy);
  the row context menu offers the state-appropriate download action. Catalogue
  rows show the `3/11` badge in the footer and Home cards over the artwork. All
  screens observe `.discourseDownloadsDidChange` and reconfigure only visible
  rows/cards.
- **Done — playback.** `DiscourseMediaFactory` prefers
  `DiscourseDownloadStore.localURL(for:)` over the remote URL, so a verified
  download plays offline through the same queue path; a missing file falls back
  to the CDN.
- **Done — tests.** `Buildsystem/Testing/Unit/DiscourseDownloadTests.swift`
  (10 cases) plus 2 playback-mapping cases = **97 unit tests, 0 failures**. A new
  UI test, `testTrackDownloadAndRemoval`, downloads a real track, waits for the
  green state, then removes it through the menu (it skips if the CDN is slower
  than 150 s): **14 UI tests, 0 failures** on the iPhone 16 Pro simulator.
- **Verified live.** Downloading track 01 of *A Bird on the Wing* produced
  `Application Support/Discourses/<audioID>.audio`, the arrow turned green, the
  row menu and the nav menu showed the right actions, the card badge read `1/11`,
  and confirming **Remove all downloads** emptied the directory. Screenshots were
  captured for detail (before/after), menu, confirmation, card badge, Home and
  Search row layouts.
- **Deferred.** The card badge replaces the brief's footer download row (§10.35).
  Downloads survive backgrounding through the background session, but a force
  quit cancels them and the row returns to the arrow (§10.37).

### Phase 13 — Audio Mixer — **Done**
- **Done — engine.** `DiscourseAudioMixer` (§4.12) owns a second
  `VLCMediaPlayer` with its own media, volume, fades and loop. Membership,
  selection, switches and volume persist under the documented `audio_mixer_*`
  keys; volume is clamped 1…100 and never follows the main player. It is created
  at launch so a previously enabled mixer follows without opening the tab.
- **Done — follow.** 250 ms after the main player starts (audio only; a video
  stops the mixer), pause/resume with it, stop on stop/fail, loop or stop at the
  end, reload on a loop toggle, fade in ~200 ms and out ~220 ms. Interruptions,
  route loss and a media-services reset pause it; the main player is paused on a
  media-services reset.
- **Done — UI.** `DiscourseAudioMixerViewController` is now a real screen: the
  panel (on switch, now playing, play/pause, loop, volume) plus the ordered list
  with selection, long-press drag reorder, swipe delete, **Clear all** (confirmed)
  and an empty state whose **Add audio file** action opens the system Files
  picker. `DiscourseMixerPanelView` and `DiscourseMixerTrackCell` carry the
  content.
- **Done — entry point.** The **+** button and empty-state action import audio
  through `UIDocumentPickerViewController`; `DiscourseMixerFileImporter` copies
  the file into app-owned storage and `DiscourseAudioMixer` persists its URL.
  The removed Local Library screen is not linked. The legacy library context
  action **Add to Audio Mixer** also remains on upstream library surfaces.
- **Done — tests.** `Buildsystem/Testing/Unit/DiscourseMixerTests.swift`
  (18 cases) pins the mixer state and file imports without a player, and
  `testAudioMixerShowsThePanelAndOpensTheAudioPicker` covers the panel, clear
  path and document picker.
- **Verified live.** A generated local track, added through the library menu,
  joined a playing discourse 250 ms after Play all, paused and resumed with the
  mini player's play/pause and showed the right panel state each time; the panel,
  row and library menu were captured as screenshots.
- **Deferred.** Mixer playback (follow, fades, loop, audio-session handling) is a
  manual check: the UI tests cannot supply local media, so the automated suite
  covers state and navigation only.

### Phase 14 — playlists styling and device-library history — **Done**
- **Done — device history.** `DiscourseLocalTrack` (§4.9) adapts
  `MediaLibraryService.medialib.audioHistory()` (title, artist/album, thumbnail,
  duration, file URL, media reference). Home's *Recently played tracks* now lists
  the discourse history followed by the library history, deduped by media
  identity (audio id / file URL) and capped together at 24, gated by the
  playback-history switch. Library rows hide the like and download controls and
  play through `PlaybackService.playMedia(at:fromCollection:)`.
- **Done — row polish.** `DiscourseRowView` drops the empty artwork slot when a
  library file has no thumbnail, clears stale artwork on reuse (a bug found while
  verifying Home), and the playing marker only applies while the player is
  actually playing (`isPlaying`) instead of leaving the last track red after a
  stop.
- **Done — playlists.** The tab keeps the upstream playlist grid and creation
  flow, but its navigation bar now uses the discourse accent and its empty state
  explains how to create a playlist from the local library instead of pointing at
  the removed Video/Audio tabs. `PlaylistViewController` applies the accent on
  launch and on theme changes.
- **Done — tests.** Four new `DiscourseHomeTests` cases (**112 unit tests, 0
  failures**); the UI suite stays at **15 tests, 0 failures**.
- **Verified live.** Playing the generated local file from the library made it
  appear on Home under *Recently played tracks* (`Rajneesh Mixer Test.m4a · 0:04`,
  no controls, no artwork slot) and tapping that row started it through the
  library player. The Playlists tab shows the new copy and the red accent.
- **Deferred.** The floating-capsule tab bar, the global discourse accent tint
  and the playlist cards' custom styling remain open (§10.18); the VLC-cone
  artwork is still upstream (§10.9).

### Phase 15 — accessibility, localisation, polish — **Done**
- **Done — playback history setting.** The in-app Settings' Playback section
  gained **Playback history** (`SettingsSection.swift`, key `playback_history`),
  and `VLCAppDelegate` registers its on-by-default value so the toggle and
  `DiscoursePlaybackSettings` agree before the first change. The video fullscreen,
  video resume, video decoding and subtitle rows were removed from the settings
  model and from both `Settings.bundle` plists (no video product surface).
- **Done — accessibility.** The mixer row announces *Playing in the mixer* as
  part of its label; a finished download is announced as status text instead of
  a button that does nothing; the mixer volume label can grow with Dynamic Type
  instead of clipping at a fixed width.
- **Done — localisation.** Every fork string goes through `NSLocalizedString`;
  the new Settings title is in the Settings bundle's `en` table (`en` is the
  development region, so other languages fall back to it). A sweep found no
  hard-coded user-facing copy in the fork screens.
- **Done — tests.** `testPlaybackHistorySettingToggles` (flip, wait, restore) in
  `VLCTestMenu`: **16 UI tests, 0 failures** (the network-bound download test
  skipped on the slow-CDN run and passes when the CDN keeps up); the unit suite
  is **113** with the launch-screen test added by the branding polish below.
- **Verified live.** The Settings screen shows *Playback history* on, with the
  video and subtitle rows gone; the light theme was exercised from the Theme
  picker and the fork screens rendered with the light `DiscourseColors` before
  the dark default was restored.
- **Remaining, documented.** The capsule tab bar and global accent were
  completed in the post-phase polish below (§10.18); the VLC-cone empty-state
  artwork and the onboarding/About marks are still upstream (§10.9), and the
  `playback_history` row is only translated into English.

### Post-phase polish — branding icon and iOS 26 tab bar — **Done**
- **App icon.** The new Rajneesh artwork replaced the upstream set in
  `AppIcon.appiconset` (iPhone, iPad, App Store and watch-role sizes; the watch
  notification-centre, launcher and quick-look entries are now filled too) and
  both iOS app targets now select `AppIcon` instead of the `VLC26*` Icon Composer
  bundles. Verified on the simulator home screen on iOS 18.3 and iOS 26.4.
- **Launch screen.** `Launch Screen.storyboard` now shows the same artwork as a
  rounded 128 pt tile on the `#0D0D0D` app background instead of the orange VLC
  cone, using a new `LaunchIcon.imageset` (160/320/480 px) exported from the
  1024 px icon. Verified from a screen recording of a cold launch on iOS 26.4.
- **Liquid Glass tab bar.** iPhone builds now stay in the default tab-bar mode
  (`.tabSidebar` is limited to iPad), so iOS 26 renders the floating Liquid Glass
  capsule; the selected item uses the discourse accent. A new
  `discourseFloatingTabBarInset` adds the covered height to the bottom inset of
  the catalogue, detail, Home and search scroll views, so their last row clears
  the floating bar. Verified on an iOS 26.4 simulator (scrolled to the bottom and
  on every tab); iOS 18.3 keeps the classic bar.
- **Tests.** 112 unit tests and 16 UI tests (download test skipped on a slow-CDN
  run) on the iOS 18.3 reference device, 0 failures.

### Post-phase polish — watchOS and tvOS artwork — **Done**
- **watchOS.** `Resources/watchOS/Assets.xcassets/AppIcon.appiconset` and
  `AppIconDev.appiconset` now use the Osho artwork, and the watch-role icons in
  the iOS `AppIcon.appiconset` were regenerated. Watch icons are opaque and pad
  the wordmark to about 80% width so the circular mask does not clip it. A
  generic watchOS build passes and the compiled watch `Assets.car` contains the
  new `AppIcon`.
- **tvOS.** The layered primary app icon (large and small, 1x/2x), top-shelf
  images, About/Settings artwork and launch tile now use the Osho artwork; the
  launch background is `#0D0D0D`. The catalog metadata loads and reports only the
  pre-existing `sort.imageset` ambiguity; a full compile/visual check is blocked
  because the tvOS simulator runtime is not installed on this machine
  (`tvOS 26.4 is not installed`).

### Post-phase polish — remove OneDrive and ADAL (UIWebView) — **Done**
- Removed the OneDrive cloud browser and its service-list row, list-cell support,
  constants, onboarding icon, `OneDriveCell` / `OneDriveWhite` assets and About
  credits.
- Removed `ADAL`, `OneDriveSDK` and the transitive `Base32` pod; `pod install`
  pruned them from `Podfile.lock` and the Pods project. The Microsoft
  `com.microsoft.adalcache` keychain group is gone from all iOS entitlements.
- The built iOS app has no `UIWebView` symbols or ADAL storyboards, resolving
  ITMS-90809. Verified with `nm -u` and an app-bundle scan.

### Post-phase polish — remove optional permissions and iCloud Documents — **Done**
- Removed the radio alarm feature, `NSAlarmKitUsageDescription` and all
  `RADIO_ALARM_*` strings.
- Removed biometric unlock from the passcode and parental-control flows,
  `NSFaceIDUsageDescription`, the `LocalAuthentication` framework link and the
  biometric settings rows.
- Removed photo-library saving: the snapshot gesture/settings and the
  Save-to-Camera-Roll share action. The `NSPhotoLibrary*UsageDescription` keys
  are gone; `PHPickerViewController` remains and needs no permission.
- Removed iCloud Documents (`CloudDocuments`, iCloud and ubiquity container
  identifiers) and the unreachable iCloud row in the upstream cloud-services
  screen. The separate `NSUbiquitousKeyValueStore` entitlement remains because
  the server list, recent URLs and Dropbox/Box credentials still use it.
- Removed the podcast background refresher, the `fetch`/`processing` background
  modes and `BGTaskSchedulerPermittedIdentifiers`; only `audio` remains in
  `UIBackgroundModes`. Finite `beginBackgroundTask` work is unaffected.
- Verified `VLC-iOS` and `VLC-iOS-no-watch` build; the built Info.plist contains
  only `NSLocalNetworkUsageDescription`.

### Post-phase polish — first-play audio session — **Done**
- `VLCPlaybackService` now activates the shared `AVAudioSession` before
  `_playNewMedia` and before a resume `play`. Previously the full player activated
  it only in `viewDidLoad`, after playback had started, so the first track could
  show as playing with no audio until pause/play.

### Post-phase polish — titles and segment tint — **Done**
- The Audio Mixer tab reads **Mixer** (`AUDIO_MIXER` key unchanged); the Home and
  Audio Mixer screens no longer show a navigation title, so their content starts
  under a compact bar (§4.1).
- The navigation-bar settings button (`AppMenuBarButtonItem`) shows the rounded
  app icon instead of the VLC cone, and the shared empty state
  (`VLCEmptyLibraryView`, used by the Playlists tab, local library, history and
  folders) shows the app logo. Both reuse `LaunchIcon`; the passcode and donation
  cones remain upstream (§10.9).
- The **Home** header uses the static app logo on the left and a chevron
  dropdown on the right that opens the app menu; the logo has no action and is
  hidden from VoiceOver. The Home section headers lost their top padding, so
  *Top discourses this week* sits directly under the compact navigation bar. The
  other screens keep their existing icon-as-menu button.
- The header menu offered **Help & Website** (opening
  `https://rajneeshdiscourse.com`) and the upstream **Donate to VideoLAN** item
  was removed; a later polish pass removed **Help & Website** too, so the app
  menu is now **About Rajneesh Discourse** and **Settings** only. The About page
  uses the branded app icon (no old VLC wordmark title),
  its website link points to `rajneeshdiscourse.com`, and **Contact us** mails
  `support@marfells.com`.

### Post-phase polish — catalogue as a one-column list — **Done**
- The Discourses tab renders the catalogue as a full-width list instead of a
  two-column grid: one `DiscourseCardCell` per row with 88 pt artwork on the
  left and the title, language, track count, download badge and heart on the
  right, 16 pt section insets and 12 pt row spacing.
- `DiscourseCardCell` gained a `Layout` (`.tile` / `.list`). Home's
  *Recently played* and *Top discourses* carousels keep the 160 pt square tile;
  the catalogue sets `.list`. Both layouts share the like control, the badge
  state and the VoiceOver overlay. The list badge lives in the footer so it
  cannot cover the smaller thumbnail (§4.9, §10.20, §10.35).
- Verified on the iPhone 17 Pro simulator (iOS 26.4): the catalogue shows one
  full-width card per row, the row height self-sizes around the 88 pt artwork,
  and the Home carousels are unchanged.

### Post-phase polish — Local library offers Songs and Folders — **Done**
- The local library opened from local-media shortcuts uses a Songs and Folders
  pages (the Mixer no longer opens it; see the file-picker polish below).
  `TabBarCoordinator` pushes `DiscourseLocalLibraryViewController` (`Sources/Discourse/UI/`), an
  `AudioViewController` subclass whose pager has Songs and Folders pages; the library's own navigation-bar actions (search, select all,
  sort, history, add external folder, Settings) and edit mode are unchanged.
- The upstream `AudioViewController` is untouched (upstream sync stays cheap).
  Its sub-tab index is ignored: the subclass pins `currentIndex` to 0 because
  `TrackCategoryViewController.viewWillAppear` still writes the old Songs index
  (2) to `kVLCAudioTabIndex`.
- The last-played shortcut's *open album* now pushes the album's
  `CollectionCategoryViewController` from the Songs page when no
  `AlbumCategoryViewController` exists (`TabBarCoordinator.showLocalLibrary(pushing:)`),
  so the quick action keeps working with the album page gone.
- Verified on the iPhone 17 Pro simulator (iOS 26.4) with a local `.m4a`: the
  library opens straight onto the Songs list, with no strip and no gap
  under the navigation bar; the empty library still shows the shared empty
  state.

### Post-phase polish — Mixer without an Edit button — **Done**
- The Audio Mixer's navigation bar no longer carries **Edit**; only the app menu
  remains on the left. The list keeps both interactions: long-press a row and
  drag it to reorder (UITableView drag & drop, `UITableViewDragDelegate` /
  `UITableViewDropDelegate`), and swipe a row to delete it (the existing
  `commit editingStyle`). The mixer's change notification is suppressed while a
  drop animates the move, so the table is not reloaded mid-drag.
- Edit mode, its `setEditing` wiring and `allowsSelectionDuringEditing` are gone
  from `DiscourseAudioMixerViewController`; taps always select/play a row.
- Verified on the iPhone 17 Pro simulator (iOS 26.4) with two seeded mixer
  tracks: the header shows no Edit button and both rows render with the
  selected checkmark, hint and **Clear all** footer.

### Post-phase polish — Mixer file picker — **Done**
- The Mixer adds files directly: **+** and the empty-state **Add audio file**
  open a single-selection `.audio` document picker. The previous **Open local
  library** action, its empty-state link, hint, notification and coordinator
  observer are removed; the removed Local Library screen is not referenced by
  the Mixer.
- `DiscourseMixerFileImporter` copies selections into
  `Application Support/AudioMixer/<source-id>/<original filename>`, balancing
  security scope and cleaning partial copies on failure. Reimports reuse the
  same copy, identical names from different sources stay separate, and row
  titles still show the original filename. `DiscourseAudioMixer` removes only
  app-owned copies on delete/clear; source and library files are untouched.
- **Verification.** `VLC-iOS-no-watch` builds. `DiscourseMixerTests` passes all
  18 cases, seven of them new import/cleanup cases.
  `testAudioMixerShowsThePanelAndOpensTheAudioPicker` passes on the iPhone 17
  Pro simulator (iOS 26.4), including opening/cancelling the real document
  picker and asserting no Local Library action exists.

### Universal Links — **Done (AASA deployment required)**
- `https://rajneeshdiscourse.com/discourses/{id}` opens the discourse detail;
  `/tracks/{audioId}` opens it and scrolls to that track (§3.8, §4.1).
- `DiscourseDeepLink` + `TabBarCoordinator.handleDiscourseDeepLink(_:)` handle
  parsing and routing; `VLCAppCoordinator` queues the URL until the passcode
  gate releases the tab bar.
- Associated Domains is in all three iOS entitlements files. The website must
  deploy `Buildsystem/DeepLinks/apple-app-site-association`; the live AASA
  returned 404 during implementation, so links still open Safari until it is
  published.
- `DiscourseDeepLinkTests` cover the parser. The route itself needs a signed
  device build because the simulator does not fetch the AASA.

### RNNoise — integrated and simulator-verified

- The audio player's options sheet has an accessible **Noise reduction** switch,
  off by default, persisted as `RDNoiseReductionEnabled`. The main
  `VLCPlaybackService` applies it through the custom VLCKit public selectors and
  posts `VLCPlaybackServiceNoiseReductionDidChange` after successful changes.
- The switch is disabled with upstream VLCKit or while casting. Failure retains
  the previous preference. Mixer playback never prepares or enables RNNoise.
- Native patches and artifact build/activation tools live in
  `Buildsystem/RNNoise/`. The filter negotiates 48 kHz input, buffers complete
  frames, resets on seeks, drains its tail and crossfades wet/dry audio without
  rebuilding the filter chain. Equalizer changes retain the RNNoise filter.
- Native device/Intel simulator/Apple Silicon simulator builds and the no-watch
  app build pass. All six `DiscourseNoiseReductionTests` pass against the activated
  engine, including real 44.1 kHz stereo playback, live toggling, equalizer
  coexistence, progress and paused switching. Native sanitizer checks cover
  framing, the real RNNoise model, allocation failures and 10,000 allocation-free
  resets; artifact packaging/activation checks also pass.
- All 132 unit tests pass with the activated engine. Unit-test installation
  currently needs temporary Watch identifier overrides (§10.45); the native
  README records the verified command. Physical-device
  listening/performance acceptance remains pending before release.

Reference files present for the contract: `api/docs.md`,
`api/types/discourse.type.ts`, `api/edge.ts`, `api/migrations/`, `api/tests/`
(backend reference material; **never wire `/seed` into the app**).

---

## 10. Known gaps and intentional deviations from Android

Google Drive is intentionally unavailable. Existing downloaded local files remain
usable; saved Drive favourites cannot open the removed browser.


Record every deviation here; never hide a gap.

1. **Architecture.** Android integrates with `PlaybackService`/`MediaUtils` and
   Android's `DownloadManager`/`SharedPreferences`. iOS integrates with
   `VLCPlaybackService`/`VLCMediaList` and uses `URLSession` download tasks,
   `UserDefaults` and Keychain. Keys keep the `osho_api_*` names; the storage
   *mechanism* differs by design.
2. **Crash/error reporting.** Android uses `ErrorReporter` (Sentry). This fork has
   no crash reporting SDK; unexpected errors are logged via
   `APLog` under a `DiscourseDiagnostics` category with screen/context tags and no
   secrets. Expected offline/cancellation/4xx are not logged as errors.
3. **Downloads.** Android's `DownloadManager` gives system UI and external storage;
   iOS uses a background `URLSession` with app-private file storage (no system
   download UI). States and behaviour match.
4. **Audio Mixer.** Android drives the mixer inside the same `PlaybackService`.
   iOS uses a dedicated second `VLCMediaPlayer` (`DiscourseAudioMixer`) coordinated
   with main-player notifications, because VLCKit exposes one player per instance.
   Observable behaviour (defaults, follow/resume, loop, fades, volume isolation)
   matches the spec.
5. **Identity.** Android stores the UUID in the Android Keystore (and legacy
   `SharedPreferences`). iOS stores it in the Keychain via `KeychainCoordinator`,
   mirrored to `UserDefaults`. Both lose the identity if the secure store is
   cleared on reinstall.
6. **Likes history.** The Android repo predates the backend `/likes` GET and
   unlike routes in places; this fork implements the full current contract
   (`GET /likes`, `DELETE /likes`, independent discourse/audio counts).
7. **Settings entry point.** Upstream iOS presents Settings modally from a bar
   button; Android has a settings tab. This fork keeps the iOS modal pattern.
8. **Test host requires watchOS runtime.** The upstream `VLC-iOS-Tests` /
   `VLC-iOS-UITests` / `VLC-iOS-Screenshots` schemes are bound to the
   watch-embedded `VLC-iOS` app target, so running them needs a watchOS simulator
   runtime installed. watchOS 26.4 is installed on this machine and the suite runs
   green (39 tests, including `DiscourseAPITests` and `DiscourseStoresTests`). On a
   fresh machine: `xcodebuild -downloadPlatform watchOS`. The day-to-day build scheme
   (`VLC-iOS-no-watch`) still has no test host; a fork-only no-watch test target
   remains an option if CI ever needs one.

9. **Branding artwork.** The launcher icon and the launch screen are now the
   Rajneesh artwork (`AppIcon.appiconset` selected via
   `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`; `Launch Screen.storyboard`
   shows `LaunchIcon.imageset` on `#0D0D0D`). The layered `VLC26*.icon` Icon
   Composer bundles stay in the project for upstream sync but are no longer
   selected. The watchOS and tvOS app icons, the tvOS top shelf/About artwork and
   the tvOS launch tile now use the Osho artwork too; the tvOS network-browsing
   cone artwork remains upstream. The onboarding illustrations and the VLC-cone
   artwork used by the passcode and donation screens are still upstream assets.
   Replacing them needs real design files. The About title mark is gone; the
   About page shows the branded app icon (`AppIcon-480x480.png`), and its
   "Contact us" action now mails `support@marfells.com` (was
   `support@sandalbar.online`). The
   navigation-bar settings button now draws the rounded app icon, and
   `VLCEmptyLibraryView` (the shared empty state behind the local library,
   playlists, history and folders) shows the app logo instead of the VLC cone.
   The menu no longer offers the upstream *Donate to VideoLAN* action.

10. **Branding scope after Phase 2.** Navigation is now complete (Phase 5) with the
    five destinations; what remains from branding is the artwork (§10.9). Local
    media playback, playlists and background audio are unaffected.

11. **HTTP timeouts.** OkHttp exposes separate connect (5 s) and read (15 s)
    timeouts. `URLSession` has a single idle timeout, so `DiscourseAPIClient` uses
    `timeoutIntervalForRequest = 15` (read) and `timeoutIntervalForResource = 30`,
    with `waitsForConnectivity = false` so an offline start fails immediately
    instead of waiting. Observed behaviour matches the spec: dead networks surface
    as an error and stale cache is served instead.

12. **Response cache.** Android relies on OkHttp's disk cache plus interceptors.
    The backend sends no cache headers, so `URLCache` would refuse to store
    anything; `DiscourseAPICache` therefore implements the policy itself (raw JSON
    per request URL, 24 h freshness, stale-on-failure, ≈10 MB cap, `/likes`
    excluded). The observable policy is identical to the spec.

13. **Page size.** The brief says 16 per page, but the deployed API returns 24
    rows per `/discourses` page and exposes no `page_size` parameter (see
    `api/docs.md`). The catalogue paginates with `page` and `meta.total_pages`
    only; there is no client-side page-size control. The list is one card per
    row, so the extra rows change the scroll length, not the layout.

14. **Identity storage.** `DiscourseIdentity` talks to
    `XKKeychainGenericPasswordItem` directly instead of going through
    `KeychainCoordinator`, which is bound to the passcode UI. The keychain service
    id is fork-specific, and the UUID is mirrored to `UserDefaults` so a keychain
    hiccup cannot orphan likes/history.

15. **Progress storage keys.** Android keeps one preferences key per track
    (`osho_progress_member.<id>` for the discourse and `osho_progress_duration.<id>`
    for the duration). iOS keeps the documented
    `osho_api_discourse_playback_position.<audioId>` keys for positions but one
    JSON index `osho_api_discourse_track_info` for the discourse/duration pairs,
    and `osho_api_discourse_completed_audios` for finished tracks. Observable
    behaviour (resume, progress rings, completion, replay-from-start) is the same;
    the mechanism avoids thousands of `UserDefaults` keys.

16. **Likes cache shape.** Android persists the liked id sets and lets the UI read
    counts from list payloads. iOS additionally remembers per-target counts in
    memory (`DiscourseLikesStore.counts`) so optimistic toggles can show a count
    immediately, and a completed refresh clears pending toggles in one step.

17. **Local library entry point.** The Discourses tab shows the catalogue
    without the Android Discourse/Local switch. The mixer empty state and local
    media shortcuts push the local library with Songs and Folders above the catalogue, and
    Back returns to the catalogue.

18. **Tab bar: the capsule is the system's, not a custom one.** The shell keeps
    `UITabBarController` (no custom geometry) and now selects the default tab-bar
    mode on iPhone, so iOS 26 draws the floating Liquid Glass capsule itself and
    older systems keep the classic bar. `TabBarCoordinator` tints the selected
    item with the discourse accent (the tab bar used to be orange). The iPad
    keeps the `.tabSidebar` layout. Fork scroll views add
    `discourseFloatingTabBarInset` so their last row clears the floating bar;
    the mini player and edit toolbar still anchor to the tab bar's top. The
    Playlists grid keeps the upstream XIB cells; restyling them would touch every
    library screen because the cell class is shared.

19. **On Air and podcasts.** Removing the On Air tab removes the only entry point
    to the upstream podcast/radio surface, so `PodcastFeedURLHandler.showPodcasts()`
    now finds no host tab and reports an error for incoming `vlc-x-callback`/
    podcast URLs. Podcasts are not part of this product's surface; the classes stay
    for upstream sync and would need a new host if podcasts ever return. The
    podcast background refresher, the `fetch`/`processing` background modes and
    `BGTaskSchedulerPermittedIdentifiers` were removed because they served only
    that unreachable surface. Finite `beginBackgroundTask` work for media
    downloads and Wi-Fi sharing is unaffected and needs no background mode.

20. **Cards show downloads as a badge, not a footer row.** The brief draws a
    download row under the card metadata; the Home carousel gives its cards a
    fixed height, so a conditional row would clip there. The Home tiles show a
    small `3/11` badge over the artwork, while the catalogue's full-width list
    row puts the same badge in its footer. Counts and states match the brief and
    the card never resizes (§10.35).

21. **Catalogue bar-button tint.** The Discourses tab inherits the upstream
    orange `tintColor` for its Settings and filter buttons.

22. **Media duration hint.** The brief's mapping multiplies `duration_seconds` by
    1000 and stores it on the media; iOS writes it to `VLCMedia.length`. libvlc
    replaces that hint once the stream reports its own length, so the value shown
    by the full player comes from the stream (it matched the payload exactly:
    1:37:49). Nothing in the UI depends on the hint beyond the first moments of
    playback.

23. **Track identity and queue serialisation.** The brief asks for a stable
    identifier that survives serialising the queue. A custom field cannot ride
    along in the last-played `.m3u` upstream writes, so the identity lives in two
    places: libvlc meta extras on the media (`rd.discourseID` / `rd.audioID`) for
    the live object, and the bounded `osho_api_discourse_media_identity` URL →
    identity index for queues restored from disk (AGENTS §7). The URL key is the
    track's `audio_url`, so a restored item resolves again without a network call.
    Phase 10 must use `DiscourseMediaFactory.identity(of:)` (never the extras
    alone) when attributing progress or stats.

24. **Full player on play.** Starting a discourse track presents the upstream
    full-screen audio player, exactly as tapping a local library track does. The
    brief's Android flow also opens its player screen; on iOS the mini player
    appears when that screen is dismissed. This is upstream behaviour and is kept
    deliberately — no fork-only "stay on the list" mode.

25. **Mini player inset.** Upstream library screens grow their bottom content
    inset by `AudioMiniPlayer.height` while the mini player is visible
    (`VLCPlayerDisplayController{Display,Hide}MiniPlayer`). The fork screens do the
    same (detail table and catalogue list) instead of leaving the last row under
    the mini player. Because the mini player is only shown after the full player
    closes, the inset changes then, not when playback starts.

26. **Track rows carry an overflow *menu*, not a button.** The brief's row
    carries a 48×48 thumbnail, like and played/download indicators and an
    overflow button. The rows now have all four indicators: the progress ring
    (speaker while playing, checkmark when finished), the download control, and
    the like control, with the duration in the metadata line. The extra actions
    (play next, add to queue, download/remove) live in the long-press context
    menu, matching the rest of the fork's rows rather than adding a second
    ellipsis affordance.

27. **Search covers tracks too.** The Android reference's `SearchViewModel`
    searches `/discourses` only and caps the list at 24 results. This fork follows
    the brief's phrase *"remote catalogue only"* and the Search tab's own copy
    (*"Find discourses and tracks in the catalogue"*): every query fetches
    `/discourses?search=` **and** `/discourse-audios?search=` and renders both
    sections, with unlimited paging instead of a 24-row cap. The API supports it
    (`api/docs.md`), and a track result is immediately playable through the same
    continuation path as a detail row.

28. **Search paging is lockstep.** Both endpoints are paginated with the same page
    number, and the accumulator follows whichever reports more `total_pages`;
    when the shorter list runs out the longer one keeps growing. This keeps a
    single scroll position and one request pair per page instead of two
    independent page counters. Sections collapse when they have no rows, and a
    failed next-page request leaves the rendered rows untouched (retried by the
    next scroll) rather than emptying the screen.

29. **Home merges two independently ordered histories.** Phase 14 completes
    *Recently played tracks*: the device library's `audioHistory()` arrives
    through `DiscourseLocalTrack` (title/artist/thumbnail/duration from
    VLCMediaLibraryKit, deduped by file URL) and plays through the upstream
    `PlaybackService.playMedia(at:fromCollection:)`. The discourse store keeps no
    timestamps (only order), so the merged list cannot interleave the two
    histories: discourse entries lead, library entries follow, and the combined
    list is capped at 24. Both sides are gated by the playback-history switch.
    The weekly top tracks section is a global list and is unaffected.

30. **The playback-history switch is a fork-only Settings row.** The key is
    `playback_history` (same name and default as the Android reference), read by
    `DiscoursePlaybackSettings`; `VLCAppDelegate` registers its default (on) so
    `UserDefaults.bool` and the toggle agree before the first change. Home hides
    *Recently played tracks* while it is off, the detail screen stops recording
    opened discourses, and the playback tracker skips both the history entry and
    `POST /stats`. The row lives in the in-app Settings' Playback section
    (`SettingsSection.swift`), not the legacy InAppSettingsKit plists; the same
    toggle was also added to both `Settings.bundle` plists for the system
    Settings app.

31. **Weekly stats refresh bypasses the 24 h payload cache.** The brief caches
    weekly top lists for 3 h, but every `/stats` GET also lives in
    `DiscourseAPICache` for 24 h, so a 3 h refresh would read that stale copy.
    `DiscourseStatsService` therefore takes a `forceRefresh:` flag, and
    `DiscourseStatsCache` sets it whenever its own TTL expires (and for windows
    other than `7_days`, which it does not cache at all). The API layer still
    serves its stale payload when the network fails, so the weekly lists survive
    offline.

32. **Progress tracking is notification glue, not a player subclass.** Android
    hooks the qualification and the progress saves into its `PlaybackService`
    events. iOS cannot add a second delegate to `VLCPlaybackService`, so
    `DiscoursePlaybackTracker` is a fork-only observer of the existing playback
    notifications, and the rules live in the player-free
    `DiscoursePlaybackProgress`. Playback time is accumulated from position
    deltas (not wall time) so a pause, buffering or a background stall cannot
    inflate it; deltas above 3 s are treated as seeks. Resume uses the upstream
    `startPosition` (0…1 fraction) applied to the first item of the queue, which
    is the only per-item hook `playMediaList` offers; later queue items start at
    zero. Completion is inferred from the position (within 1 s of the end) because
    the service does not surface `VLCMediaPlayerStateEnded` to observers.

33. **The player's heart needs a known payload.** The audio player's like control
    is driven by the identity on the current media plus the payload in
    `DiscourseTrackRegistry`. A queue restored from the last-played playlist has
    an identity (the URL index, §10.23) but no payload until the tracker fetches
    the discourse after the 60 s qualification, so the heart is hidden rather
    than showing a guessed count. Liking a track from a list is unaffected; the
    player heart reappears once the payload is registered.

34. **Cards and rows are accessibility containers, not single elements.** Before
    Phase 11 each card/row was one `.button` element that opened the discourse or
    played the track, which would have hidden the heart from VoiceOver. They are
    now containers: a transparent `DiscourseAccessibilityButton` keeps the
    open/play element and its label, and `DiscourseLikeControl` is a second
    element. Touch behaviour is unchanged (the transparent view is not
    interactive; table/collection selection still fires), and the cell keeps its
    `accessibilityIdentifier` for UI tests.

35. **The card download badge replaces the brief's footer row.** A conditional
    footer row cannot work on the Home carousel, whose cards have a fixed height.
    Home tiles show a `3/11` pill over the artwork (green when finished, accent
    while downloading) and keep their size; the catalogue list row places the
    same pill in its footer; the detail screen owns the per-discourse download
    actions.

36. **Download arrows toggle completed downloads.** Tapping downloads, cancels,
    retries or removes a completed download. The shared action applies to detail,
    Home and search track rows; VoiceOver announces completed arrows as removal
    buttons. Removing all downloads still asks for confirmation. Detail track
    cards use 14 pt vertical content padding.

37. **Failed downloads are reported by their icon, not an alert.** A failure
    leaves an exclamation arrow (accessibility label *Download failed … Tap to try
    again.*) until a retry or removal, so a flaky CDN cannot stack alerts — the
    brief's "report repeated failures once" holds by construction. Background
    transfers survive suspension and relaunch (the session re-attaches by
    `taskDescription`), but a force quit cancels them: the row returns to the
    plain arrow and no partial file is left, because URLSession writes outside
    the downloads directory until the transfer finishes.

38. **The mixer's selection is stored as a URL, not an index.** The documented
    `audio_mixer_selected` key is a string; keeping the URL means reordering can
    never point at the wrong track, and a selection whose file disappeared falls
    back to the first item. A missing file simply fails to open instead of
    crashing.

39. **Mixer rows show file names.** `audio_mixer_files` is documented as plain
    URL/bookmark strings, so no library metadata is persisted. The list shows the
    file name without its extension; persisting titles would need a second key
    the contract does not define, and resolving them through the media library
    would make the list depend on the library being loaded.

40. **End of track is `.stopped` in VLCKit 4.** The public
    `VLCMediaPlayerState` enum has no `ended` case, so the mixer flags the stops
    it requested (`isStopping`) and treats an unrequested `.stopped` as the end
    of the track, which is where loop/stop applies.

41. **The mixer always follows main playback.** The panel's play button arms
    the mixer while the main player is idle; it cannot start standalone playback.

42. **Video detection uses the player's track list.** The mixer stops when
    `numberOfVideoTracks > 0` and `playAsAudio` is false, the same test the player
    display controller uses to pick the audio or video controller. A video opened
    as audio keeps the mixer running.

43. **Clear all asks first.** The brief lists "clear" without a confirmation. The
    iOS screen asks ("Remove every track from the Audio Mixer?") because it is a
    destructive, irreversible action, matching the download remove-all pattern.

44. **RNNoise requires the custom engine.** The upstream VLCKit binary contains
    RNNoise but lacks a public live-toggle API. Until the custom artifact is built
    and activated, the switch is disabled. Seamless switching keeps the denoiser
    warm while bypassed and adds a fixed 20 ms delay to main-player audio; CPU and
    battery cost remain when the switch is off. Physical-device acceptance is
    required before release. Native build details and source pins are in
    `Buildsystem/RNNoise/README.md`.

45. **Watch signing identifiers.** The app uses bundle ID `com.oshodiscourse`;
    the Watch app uses `com.oshodiscourse.watchos` and names the app as its
    companion in all configurations. Earlier simulator verification used a
    temporary `XCODE_XCCONFIG_FILE`; the repository settings now carry the same
    IDs directly. A valid team profile is still required for signed builds.

46. **Deep links use Universal Links, not a custom scheme.** The website links
    are `https://rajneeshdiscourse.com/...`; Android uses an https intent filter,
    iOS uses Associated Domains plus the AASA file. The API has no fetch-by-id
    route, so a cold deep link reconstructs the discourse metadata from
    `/discourse-audios?discourse_id=` (history/registry cache first, then a
    catalogue search by title, then the track payload; the Android reference
    uses the same track-list fallback). The detail screen then loads the tracks
    from the 24 h cache. If the AASA is missing, iOS opens Safari; the deployable
    file is `Buildsystem/DeepLinks/apple-app-site-association`.

47. **Donation nag.** The recurring “Donate today” launch modal, its monthly and
    launch-count gate, controller, XIB and localized strings were removed. The
    separate first-run onboarding flow and underlying donation support remain.

48. **Local audio access is folder-scoped.** iOS has no app-wide authorization
    status for scanning audio files. The Local Songs empty state uses a resolvable
    external-folder bookmark to distinguish the add-folder prompt from “No files
    found”; both offer the picker, which grants access to a selected folder. This
    is not a system-wide permission-denied check.

49. **Local library has one pager page.** `AudioViewController` normally restores
    the saved five-page audio index. `DiscourseLocalLibraryViewController` resets
    the index before entering the inherited appearance lifecycle and pins it to 0,
    because the Discourses/Local root contains only the Songs page. After the
    view appears, it lays out and refreshes the pager so the Songs page is attached
    even if the initial layout had zero width. The empty check uses the model:
    an empty grouped collection can have zero sections.

50. **Mixer imports are app-owned copies.** A `UIDocumentPickerViewController`
    URL is security-scoped and may stop resolving after relaunch unless a
    bookmark is persisted. `DiscourseMixerFileImporter` instead copies each
    selection to `Application Support/AudioMixer/<source-id>/<filename>` and
    stores that plain file URL, so playback needs no bookmark and survives a
    missing original. The copy is idempotent per source, identical filenames
    from different sources stay distinct, and removing a mixer track or clearing
    the list deletes only the copy. The removed Local Library screen is not a
    Mixer destination.

51. **Optional permissions intentionally removed.** The fork no longer ships
    radio alarms (AlarmKit), Face ID/Touch ID unlock, photo-library saving or
    iCloud Documents. This removes `NSAlarmKitUsageDescription`,
    `NSFaceIDUsageDescription` and both `NSPhotoLibrary*UsageDescription` keys;
    the only runtime privacy prompt left is Local Network. The iCloud
    key-value store entitlement stays because `NSUbiquitousKeyValueStore` still
    backs the server list, recent URLs and Dropbox/Box credentials. iCloud Drive
    folders selected through the system document picker remain readable without
    the app's own iCloud Documents container.

*(Add new deviations here as they are discovered during implementation.)*

---

## 11. Upstream sync policy

Keep Google Drive sources and tests out of target build phases when syncing
upstream; do not restore Google Sign-In pods, cloud entries or OAuth registration.
Upstream licence notices and source attribution are retained.


This fork tracks VLC for iOS `master`. To merge upstream without losing fork
behaviour:

1. Keep fork-only code in clearly named files/directories
   (`Sources/Discourse/`, `Discourse*` types) and touch upstream files as little as
   possible. Prefer adding behaviour in a new file/category over editing upstream
   classes; where an upstream file must change (e.g. `TabBarCoordinator`,
   `VLCPlaybackService+MediaLibrary`, `VLCMetadata`), keep the edit small and
   self-contained.
2. Maintain a short list of "fork touch points" — upstream files we intentionally
   edit — and update it whenever a new one is added. Keep the list here:

   - `Sources/Playback/Control/VLCPlaybackService.{h,m}` — main-player RNNoise
     capability checks, preference, live switching and renderer transitions,
     plus audio-session activation before the first play and resume.
   - `Sources/Playback/Player/PlayerViewController.swift`,
     `Sources/Playback/Player/AudioPlayer/AudioPlayerViewController.swift` and
     `Sources/Playback/Player/VideoPlayer-iOS/VideoPlayerViewController.swift` —
     buffering uses a plain white `UIActivityIndicatorView` instead of the VLC
     pulsing cone.
   - `Sources/Playback/Player/VideoPlayer-iOS/MediaMoreOptionsActionSheet.swift`,
     its `Subviews/MediaPlayerActionSheet.swift`, and
     `Sources/UI Elements/ActionSheet/ActionSheetCell.swift` — audio-only noise
     reduction switch, status, availability and accessibility.
   - `Buildsystem/RNNoise/` — pinned native patches, tests, local binary package
     and artifact build/activation commands. Rebase these patches explicitly
     when upgrading VLCKit/libvlc; do not drop the equalizer preservation change.
   - `Sources/App/iOS/TabBarCoordinator.swift` — five-tab Rajneesh navigation,
     tab-index persistence, catalogue navigation, local library shortcuts,
     and album deep-link routing, the one-time `DiscoursePlaybackTracker` start,
     the launch/foreground `GET /likes` refresh, the launch-time
     `DiscourseAudioMixer` singleton and the `MediaLibraryService` handed to the
     Home screen for its library history. The Mixer no longer routes to the
     removed Local Library screen. It also handles the website Universal
     Links (`handleDiscourseDeepLink:`) and pushes the detail screen.
   - `Sources/App/iOS/VLCAppDelegate.m` — `NSUserActivityTypeBrowsingWeb` and
     direct https URLs are routed to the discourse deep link; the tab bar can be
     behind the passcode gate.
   - `Sources/App/VLCAppCoordinator.{h,m}` — queues a deep link received before
     `setTabBarController:` and releases it once the tab coordinator exists.
   - `Resources/iOS/VLC.entitlements`, `VLC-iOSDebug.entitlements`,
     `VLC-iOS-no-watchDebug.entitlements` — Associated Domains
     (`applinks:rajneeshdiscourse.com`).
   - `Sources/Discourse/DeepLink/DiscourseDeepLink.swift` and
     `Buildsystem/DeepLinks/` — the URL parser, its tests, the deployable AASA
     and the website deployment note. The detail screen's
     `highlightedAudioID` scrolls to the linked track.
   - `Sources/Media Library/MediaViewControllers/PlaylistViewController.swift` —
     the fork accent on the Playlists tab's navigation bar (applied on launch and
     on theme changes).
   - `Sources/App/iOS/TabBarCoordinator.swift` (tab-bar part) — the default
     tab-bar mode on iPhone, `.tabSidebar` on iPad only, and the discourse accent
     tint for the selected item.
   - `Sources/Discourse/UI/DiscourseFloatingTabBar.swift` — the covered-height
     helper (`discourseFloatingTabBarInset`) used by the fork scroll views on
     iOS 26.
   - `Sources/Discourse/UI/DiscourseSegmentControl.swift` — the Discourses tab's
     former Discourses switcher; retained as an unused fork component.
   - `Sources/Discourse/UI/DiscourseLocalLibraryViewController.swift` — the
     fork's Local library: an `AudioViewController` subclass reduced to one
     Songs page, so the upstream sub-tab strip is gone while the library's bar
     actions and edit mode keep working. It marks that page for the Local empty
     state and resets the inherited audio index before appearance. `TabBarCoordinator`
     pushes it and uses the Songs page when an album deep link needs a push.
   - `Resources/iOS/Images.xcassets/AppIcon.appiconset` and the
     `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` setting on `VLC-iOS` and
     `VLC-iOS-no-watch` (Debug/Release/Distribution) — the Rajneesh launcher
     icon. The `Resources/iOS/VLC26*.icon` bundles are no longer selected.
   - `Resources/iOS/Launch Screen.storyboard` and
     `Resources/iOS/Images.xcassets/LaunchScreen/LaunchIcon.imageset` — the
     branded splash (rounded icon on `#0D0D0D`), covered by
     `DiscourseLaunchScreenTests`. `LaunchIcon` is also the source for the
     navigation-bar settings icon and the shared empty-state artwork.
   - `Resources/watchOS/Assets.xcassets/AppIcon.appiconset`,
     `Resources/watchOS/Assets.xcassets/AppIconDev.appiconset`,
     `Resources/tvOS/Images.xcassets/App Icon & Top Shelf Image.brandassets`,
     `Resources/tvOS/Images.xcassets/about-app-icon.imageset`,
     `Resources/tvOS/Images.xcassets/LaunchCone.imageset` and
     `Resources/tvOS/Launch Screen.storyboard` — the Osho artwork for the watch
     and Apple TV shells: opaque circular-safe watch icons, the layered TV app
     icon, dark top-shelf and About banners, and the launch tile on `#0D0D0D`.
   - `Sources/UI Elements/Buttons/AppMenuBarButtonItem.swift` — the settings bar
     button and its About menu item draw the rounded app icon instead of
     `MenuCone`; the file also carries `AppLogoBarButtonItem` (the non-interactive
     Home logo) and the `.dropdown` style used for Home's right-hand menu
     chevron. The menu is **About Rajneesh Discourse** + **Settings** only: the
     upstream donation item and the fork's **Help & Website** link were removed.
   - `Sources/About/AboutController.swift`, `Sources/About/iOS/About Contents.html`
     and `Resources/iOS/AppIcon-480x480.png` — the About page removes the old VLC
     wordmark header, shows the branded app icon, links to
     `rajneeshdiscourse.com` and mails `support@marfells.com`.
   - `Sources/Discourse/UI/DiscourseHomeViewController.swift` and
     `DiscourseHomeSectionHeaderView.swift` — the Home header uses the static
     logo plus the right dropdown, and the section headers are tightened so the
     first title sits directly under the compact bar.
   - `Sources/Media Library/VLCEmptyLibraryView.{h,m,xib}`,
     `Sources/Media Library/MediaCategories/MediaCategoryViewController.swift`
     and `Sources/Media Library/MediaViewControllers/MediaViewController.swift` —
     the shared empty state shows the app logo; the Discourses/Local Songs empty
     state reflects external-folder access and reuses the existing folder picker.
   - `Resources/en.lproj/Localizable.strings` — `EMPTY_NO_PLAYLISTS_DESCRIPTION`
     and `EMPTY_PLAYLIST_DESCRIPTION` rewritten for this fork (no Video/Audio
     tabs; add from the local library).
   - `Sources/Settings/Model/SettingsSection.swift` — the in-app Settings model
     gains the fork's **Playback history** toggle and drops the video/subtitle
     items.
   - `Resources/iOS/Settings.bundle/Root.plist`,
     `Resources/iOS/Settings.bundle/Root.inApp.plist` and
     `Resources/iOS/Settings.bundle/en.lproj/Root.strings` — the same toggle for
     the system Settings app and the removed video/subtitle groups.
   - `Sources/Settings/Controller/PasscodeLockController.swift`,
     `Sources/Helpers/KeychainCoordinator.swift`,
     `Sources/Helpers/ParentalControlCoordinator.swift`,
     `Sources/Network/Radio/VLCRadio*`,
     `Sources/Playback/Player/VideoPlayer-iOS/VideoPlayerViewController.swift`,
     `Sources/Cloud/Services List/VLCCloudServicesTableViewController.m`,
     `Resources/*.lproj/InfoPlist.strings`, the app entitlements and
     `Resources/iOS/Settings.bundle` — the fork's removal of AlarmKit,
     biometric unlock, photo-library saving and iCloud Documents; Local Network
     is the only remaining runtime privacy prompt.
   - `Sources/App/iOS/VLCAppDelegate.m` — registers `playback_history = YES`
     (alongside the existing default registrations) so the toggle reads on
     before the user changes it.
   - `Sources/Media Library/MediaCategories/MediaCategoryViewController.swift` —
     the long-press menu gains the fork-only **Add to Audio Mixer** action for
     local audio media (inserted before the editing actions).
   - `Sources/Discourse/Mixer/` — the Audio Mixer engine and its panel/row views
     (`DiscourseAudioMixer`, `DiscourseMixerPanelView`,
     `DiscourseMixerTrackCell`) plus `DiscourseMixerFileImporter`, which copies
     document-picker files into app-owned storage. New fork-only folder; the
     engine only listens to the main player's notifications and never edits it.
     Removing a mixer item deletes only its own imported copy.
   - `Sources/Playback/Player/AudioPlayer/AudioPlayerViewController.swift` — the
     fork-only discourse like control in the audio player's `MediaNavigationBar`
     (inserted before the more-options button, hidden unless the current media has
     a known discourse payload).
   - `Sources/Helpers/VLCAccessibilityIdentifier.swift` — added `home`,
     `discourses`, `search`, `audioMixer` identifiers, plus `discourseLike` for
     the player's heart.
   - `Buildsystem/Testing/UI/VLCTestMenu.swift` — rewritten for the five-tab shell
     and catalogue navigation; carries the like round-trip test and waits for
     each toggle to settle before the next tap.
   - `Sources/App/VLCAppCoordinator.{h,m}` — register discourse/mixer services.
   - `Sources/UI Elements/PresentationTheme.swift` — dark default + fork palette.
   - `Sources/Headers/VLCConstants.h` — fork defaults/keys.
   - `Resources/iOS/Info.plist`, `Buildsystem/SharedConfig.xcconfig` — name/bundle.
   - `Sources/About/*`, `Sources/Onboarding/*` — branding.
   - `Sources/Discourse/Playback/` — the discourse playback bridge
     (`DiscourseMediaFactory`, `DiscoursePlayback`, `DiscoursePlaybackProgress`,
     `DiscoursePlaybackTracker`, `DiscourseTrackRegistry`). It is a new fork-only
     folder, not a category on `VLCPlaybackService`: it only builds
     `VLCMedia`/`VLCMediaList`, calls the existing public entry points and
     observes the existing notifications, so upstream playback code needs no
     edits. `DiscourseMediaFactory` now also prefers a verified download over the
     remote URL.
   - `Sources/Discourse/Downloads/` — the durable store
     (`DiscourseDownloadStore`) and the background transfer manager
     (`DiscourseDownloadManager`). New fork-only folder; it never touches the
     playback pipeline beyond the media URL the factory chooses.
   - `Sources/App/iOS/VLCAppDelegate.m` — one added `UIApplicationDelegate`
     method forwarding `handleEventsForBackgroundURLSession:completionHandler:`
     to the download manager, so background downloads can finish while the app
     is suspended.
   - `Sources/Discourse/UI/DiscourseCatalogueViewController.swift` and
     `DiscourseCardCell.swift` — the one-column catalogue list (full-width rows,
     artwork left) and the card's `.tile`/`.list` layouts; card selection pushes
     the detail, the collection observes the mini-player notifications for its
     bottom inset, seeds the like counts and reconfigures its visible rows on
     `.discourseLikesDidChange`, and draws the `3/11` download badge on
     `.discourseDownloadsDidChange`.
   - `Sources/Discourse/UI/DiscourseLikeControl.swift`,
     `DiscourseLikeActions.swift` and `DiscourseAccessibilityButton.swift` — the
     one heart renderer, the shared toggle/failure helper and the transparent
     VoiceOver "open" element used by cards and rows (new fork-only types).
     `DiscourseDownloadControl.swift` and `DiscourseDownloadActions.swift` do the
     same for downloads.
   - `Sources/Discourse/UI/DiscourseSearchViewController.swift`,
     `DiscourseSearchCell.swift` and `DiscourseSearchResults.swift` — the tab's
     navigation root gains a `UISearchController`, pushes the detail and starts
     tracks through `DiscoursePlayback`, and observes the mini-player
     notifications; the accumulator and row are new fork-only types.
   - `Sources/Discourse/UI/DiscourseHomeViewController.swift`,
     `DiscourseHomeContent.swift`, `DiscourseHomeSectionHeaderView.swift`,
     `DiscourseHomeTrackCell.swift` and `DiscourseRowView.swift` — the Home tab
     and the row shared with search; `DiscourseDetailViewController.swift` now
     records the opened discourse in `DiscourseHistoryStore`, registers the
     track durations and refreshes rows on progress changes, and
     `DiscourseTrackCell.swift`/`DiscourseTrackProgressView.swift` draw the
     progress ring, speaker and completed checkmark; Phase 11 added the heart to
     the header and the rows and moved the row duration into the metadata line;
     Phase 12 added the download control, the nav-bar download menu and the
     row/card download observers; Phase 14 merged the device library's history
     into Home through `DiscourseLocalTrack` and taught the row to drop the
     artwork slot and the controls for library entries.
   - `Sources/Discourse/UI/DiscourseAudioMixerViewController.swift` — the Audio
     Mixer tab's real screen (panel header, track list, clear confirmation, empty
     state); replaces the Phase 5 placeholder. No Edit button: the list reorders
     by long-press drag and deletes by swipe. The **+** button and empty-state
     **Add audio file** action open the document picker; no Local Library link
     remains.
   - `Sources/Discourse/Stores/DiscoursePlaybackSettings.swift` — the
     `playback_history` switch (no upstream key exists).
     `Sources/Discourse/Stores/DiscourseStatsCache.swift` — `DiscourseStatsService`
     gained `forceRefresh:` so a 3 h refresh bypasses the API layer's 24 h cache.
   - `Sources/Headers/VLC-iOS-Bridging-Header.h` — two added `#import`s: the
     generated `DiscourseSecrets.h` and `VLCNetworkImageView.h` (catalogue cards
     reuse the upstream cached image view instead of a second image pipeline).
   - `VLC.xcodeproj/project.pbxproj` — the *Generate Discourse API Secrets* run
     script phase and `HEADER_SEARCH_PATHS` entries on the iOS app targets and
     `VLC-iOSTests`; new fork sources/tests are registered with
     `Buildsystem/scripts/add_to_xcodeproj.rb` (never hand-edited UUIDs).

3. When merging upstream: rebase/cherry-pick onto `master`, resolve conflicts by
   preserving fork behaviour, re-run `pod install`, rebuild, and re-run the
   verification matrix in §8. Update §9/§10 as needed.
4. Never let an upstream sync silently drop the rebrand, the five-tab
   navigation, the dark default, or the discourse/mixer layers.

---

## 12. Delivery order

1. `AGENTS.md` + build/run/test documentation. *(this file)*
2. Branding, app name, icons, website links, dark-default theme, removal of
   Browse/Videos.
3. API client, models, anonymous identity, cache, error mapping.
4. Persistent stores: likes, recently played, stats dedupe, playback positions,
   catalogue filters.
5. Five-tab navigation shell.
6. Discourses catalogue + filters + paging.
7. Discourse detail + track actions + queue continuation.
8. Search.
9. Home sections + weekly stats.
10. Playback integration: metadata, resume, progress, 60-second stats/history.
11. Likes UI across cards/detail/player.
12. Downloads.
13. Audio Mixer.
14. Playlists styling and discourse-track integration.
15. Accessibility, localisation, polish, full test pass.

Phases 1–4 must not be skipped. The Audio Mixer is never implemented before the
main playback state is stable.

### Mixer file import

Mixer always offers **Add audio file** through its **+** navigation button and
its empty-state action, including when its saved track list is populated. The
system document picker accepts audio files from Files and installed document
providers. `DiscourseMixerFileImporter` copies each selection into
`Application Support/AudioMixer/` so playback survives relaunch without a
security-scoped bookmark. The original file is untouched; removing a row or
clearing the list deletes only the app-owned copy. The removed Local Library
screen is not linked from Mixer.

### Mixer control card design

The mixer header uses a collapsible Background Music Mixer card with Mixer on/off
and Loop buttons, an options menu containing the selected track and play/pause,
and a labelled volume slider with one-percent minus/plus buttons. The panel stays
in its existing table-header position; the track list and playback engine are unchanged.

Detail track rows support swiping left to reveal Add to Playlist. The action opens
the existing VLC playlist picker (or playlist creation when none exist) and saves
the streaming URL plus discourse identity so removing a download preserves the entry.

Expanded audio player: portrait has a Like / Discourse / Playlist / Noise action
row above the timeline, circular accent play button, and 30-second backward/forward
jumps in place of previous/next. Artwork blur is supported on iOS 15 and later.
Discourse dismisses the player and routes to the current discourse; Playlist uses
the existing picker presented from the player. Noise uses the existing RNNoise toggle.
The action row is hidden in landscape to preserve the compact controls.
