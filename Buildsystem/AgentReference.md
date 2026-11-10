# Rajneesh Discourse iOS — Detailed Agent Reference

Read the relevant section when directed by [AGENTS.md](../AGENTS.md). This is part of the repository contract; keep it current with related code changes. Section numbers match AGENTS.md.

## 4. Architecture map

VLC for iOS `4.0.0` (build 715), deployment target iOS 15.0, mixed Swift + ObjC: `main.m` → `VLCAppDelegate` → UIKit
scene delegate.

### 4.1 Shell, navigation, theming

- `Sources/App/iOS/VLCAppSceneDelegate.m` sets `VLCBottomTabBarController` as root, applies the theme, then hands it to
  `VLCAppCoordinator` (which owns `TabBarCoordinator`, the media library and the mini-player overlay).
- Tabs, in order, each in a `UINavigationController` with an SF Symbol and `VLCAccessibilityIdentifier`:
  `DiscourseHomeViewController` (`HOME`), `DiscourseCatalogueViewController` (`DISCOURSES`, catalogue root),
  `DiscourseSearchViewController` (`SEARCH`), `PlaylistViewController` (`PLAYLISTS`),
  `DiscourseAudioMixerViewController` (`AUDIO_MIXER`, shown as **Mixer**). Video library/player/preview screens,
  network browser and On Air implementations are excluded from both iOS targets.
- Selected index persists as `TabBarIndex` (0…4). iPhone keeps the system tab bar (iOS 26 Liquid Glass capsule;
  `.tabSidebar` is iPad only) and tints the selected item with the discourse accent; fork scroll views add
  `discourseFloatingTabBarInset` on iOS 26.
- Settings is modal from `AppMenuBarButtonItem` (**About Rajneesh Discourse**, **Privacy Policy**, **Settings**); Home uses a static logo
  with a right-hand chevron dropdown. Home, Search and Mixer share `DiscourseScreenViewController` and
  `DiscourseEmptyStateView`; Home and Mixer have no navigation title, the catalogue owns its collection view.
- About retains Contact and Done and adds a header dropdown with **Privacy Policy**. Both privacy menu actions
  open `https://rajneeshdiscourse.com/privacy` in the system browser using the same localized UIAction.
- The device library is not a tab: `DiscourseLocalLibraryViewController` (an `AudioViewController` reduced to Songs +
  Folders) is pushed above the catalogue by `TabBarCoordinator.showLocalLibrary(pushing:)`.
- iOS excludes upstream network/cloud browsers, Wi-Fi upload/web control, podcasts/radio, donations, onboarding,
  and legacy Transfers from both app targets, including their resources. CarPlay exposes library/playlists only;
  radio/video App Intents and their Spotlight entity association are removed. Files opening and discourse universal
  links remain; generic streaming, podcast and cloud-auth schemes/handlers are absent on iOS. The OS remote-command
  service is retained for lock-screen/Control Center audio. Run `ruby Buildsystem/scripts/check_ios_feature_surface.rb`
  after upstream merges or target-membership changes. Other platform source files remain available for upstream sync.
- Theming: `PresentationTheme.current` + `ColorPalette` (semantic hex, no asset colour sets); changes post
  `.VLCThemeDidChangeNotification` (`"themeDidChangeNotfication"`, upstream spelling). Fork screens use
  `DiscourseColors` (brief tokens, `.light`/`.dark`), never `ColorPalette`; dark is the first-launch default. The shell
  is programmatic (no main storyboard; ~35 legacy XIBs remain).

### 4.2 Playback

- **One `VLCMediaPlayer`**, owned by `VLCPlaybackService` (`Sources/Playback/Control/`) and created from a
  `VLCMediaListPlayer`; the service is the player, list-player and media delegate. Notifications and the public API are
  in `VLCPlaybackService.h` (start/pause/resume/will-stop/stop/fail/metadata/rate/position/mode/shuffle/next-item/
  sleep-timer/last-playlist).
- Queue = `VLCMediaList` (`mediaList` + `shuffledList`); auto-advance posts
  `VLCPlaybackServicePlaybackDidMoveOnToNextItem` and `nextMediaIndex:` decides repeat/shuffle. The canonical entry
  point is `VLCPlaybackService+MediaLibrary.m` → `playMediaList:firstIndex:subtitlesFilePath:`; discourse playback
  reuses it (§4.7).
- `VLCMetaData` is the only writer of `MPNowPlayingInfoCenter`; `VLCRemoteControlService` handles remote commands.
  Background mode is `audio` only; the service activates `AVAudioSession` before the first play/resume (VLCKit owns
  its category) and handles interruptions, route changes and backgrounding. No `setCategory:` in app code.
- Mini player: `VLCPlayerDisplayController` + `VLCAudioMiniPlayer`. Full iOS player: `AudioPlayerViewController`
  (discourse heart before more-options; Share row for a discourse track); buffering is
  a plain white spinner. The player’s Discourse header action uses the current media identity’s `discourse_id` and
  remains enabled while the full track payload is being fetched. Disabled Clip and Download controls stay white
  in both themes for contrast. Expanded audio artwork swipes horizontally: left = Next, right = Previous (commit
  at ¼ width or 500 pt/s; Reduce Motion uses a cut).
- **Audio-only iOS playback.** The main VLC library uses `--no-video` / `--no-spu`, also applied through the existing
  media-options dictionary for queued/restored tracks. Native dialog handling binds to the player's private library.
  Mixed containers and embedded artwork never switch players;
  `playAsAudio` is always true on iOS so the mixer follows their audio normally. Metadata identifies mixed
  containers as audio for lock-screen controls. The display coordinator reuses the existing audio presentation,
  dismissal and mini-player paths. Queue callbacks use `QueueViewControllerDelegate`
  rather than downcasting to the removed video player. Video-only screens/resources, PiP, external-display scenes,
  video filters, 360-degree motion and subtitle downloading are excluded from iOS targets. A container reporting
  video tracks and no audio tracks fails with “This file doesn’t contain a playable audio track.” before a resume
  notification; native failures retain the existing generic error. Share-extension metadata no longer
  advertises movies. Audio casting/AirPlay, local Files, playlists and AVFoundation clip-to-video export remain.
  Shared decoder/API types stay in VLCKit for compatibility with the existing engine and other platform targets.
- **Paused queue restoration (iOS only).** `VLCPlaybackService` checkpoints
  `Application Support/PlaybackSnapshot.json` (version 1: queue URLs, display metadata, optional artwork URL, discourse ids, selected index,
  shuffle order, repeat mode, duration, position ms); `RDPlaybackSnapshot` (`DiscoursePlayback.swift`) validates and
  writes atomically. It saves on queue/track change, seek, pause, stop, background, and every 5 s while playing. The
  scene requests restoration once after the passcode gate; a new playback request wins. Restoration uses the
  configure-only path (mini player paused) and applies the position once seekable; stop and natural completion keep the
  final position (bypassing the near-end restart rule). Missing files and offline streams keep metadata for retry;
  restoration sends no start notification or stats. `RDPlaybackSnapshotMigrationAttempted` marks the one-time legacy
  `.m3u` fallback; corrupt snapshots leave the player empty. Artwork URLs are restored for both player views. If an
  older snapshot has no URL, the playback tracker fetches the current audio object and applies its
  `discourse_thumbnail_url`, then refreshes the service metadata so both player views display it; explicit track
  artwork takes precedence over a local-library thumbnail.
  The mixer never auto-starts. Periodic five-second checkpoints reuse the last queue metadata and
  serialize/write on the snapshot queue; pause/seek/stop/background and queue changes rebuild metadata and
  synchronously drain that queue. Full queue construction uses membership/index maps instead of nested scans.

### 4.3 Library, networking and storage

- Library: VLCMediaLibraryKit (`VLCMediaLibrary`, `VLCMLMedia`, `VLCMLPlaylist`, …) over SQLite in
  `Library/MediaLibrary/`; `MediaLibraryService` is the only entry point (setup, fetch, playlists, playback state,
  `MediaLibraryObserver`). iOS has no global audio permission: access is per external folder via the document picker
  (`addExternalFolder(at:)`); the Local Songs empty state distinguishes "No files found" from "add a folder".
- HTTP: URLSession for discourse requests/downloads, `VLCThumbnailsCache`/`VLCNetworkImageView`,
  Firebase Analytics (needs gitignored `Resources/iOS/GoogleService-Info.plist`). **No crash SDK**: `APLog` and
  `DiscourseDiagnostics` only.
- Settings are `NSUserDefaults` keys in `VLCConstants.h` (registered in `VLCAppDelegate`). Keychain via
  `KeychainCoordinator`/XKKeychain (services `org.videolan.vlc-ios.{passcode,parentalControl}`,
  `online.sandalbar.rajneesh-discourse.identity`). Files: `Favorites.plist`, `Radio.plist`, last-played `.m3u`,
  snapshot, downloads, mixer imports.
- About: `AboutController` + `iOS/About Contents.html` (branded icon, site link, `support@marfells.com`). Launch
  screen: branded tile on `#0D0D0D`. Settings model: `Sources/Settings/Model/SettingsSection.swift` plus
  `Settings.bundle`. Localisation: `NSLocalizedString` over `Resources/<lang>.lproj`, new strings in `en.lproj`.
- Pinned iOS playback/UI dependencies: local RNNoise VLCKit (patched `4.0.0-a25`), VLCMediaLibraryKit `0.15.0-b2`,
  XKKeychain `1.0.3`, OBSlider `1.1.3`, MarqueeLabel `4.5.3`; Firebase Analytics remains the only direct Pod.
  pcloud is removed from the package graph; CocoaHTTPServer remains for other platforms and is unlinked from iOS.
  Box and ObjectiveDropboxOfficial are removed from the Podfile/lockfile. Subscription caching is disabled on iOS;
  the local library's existing artwork cacher remains.

### 4.4 Discourse API layer (`Sources/Discourse/API/`)

Foundation-only so models, resolver and cache test without the app. `DiscourseAPIClient` sends
`x-api-key: RD_API_KEY` to `RD_API_BASE_URL`: `discourses`, `discourse-audios`, `discourseTracks`, `likes`,
like/unlike, `stats`, `discourseStats`, `audioStats`, plus SWR readers `cached*`. Fresh GETs (24 h) come from
`DiscourseAPICache`; force refresh sends `Cache-Control: no-cache`; `/likes` is never cached; cancellation is
`.cancelled` and never serves cache; transport/5xx failures serve stale payloads. Catalogue, detail, search and Home
render any cached payload first and revalidate (SWR). `DiscourseModels` mirrors `api/types/discourse.type.ts` and additionally decodes optional discourse `date`/`location` strings returned by the catalogue; missing/null values remain nil through older caches and favourite payloads;
`DiscourseURLResolver` accepts absolute HTTPS and resolves relative paths against `https://osho.b-cdn.net/OSHO/`.
`DiscourseIdentity` keeps one UUID in the keychain (mirrored to `osho_api_user_id`); `DiscourseAPIError`/
`DiscourseErrorCopy` own the copy; `DiscourseDiagnostics` logs without the key, UUID or payloads. Cache files live in
`Caches/DiscourseAPI/` (SHA-256 keys, 10 MB cap, oldest evicted).

### 4.5 Discourse stores (`Sources/Discourse/Stores/`)

One singleton per concern on `DiscourseSettings` (typed `UserDefaults`, defensive JSON), each serialised on a queue and
injectable (settings, service, date provider, notification centre). Changes post `.discourseLikesDidChange`,
`.discourseHistoryDidChange`, `.discoursePlaybackProgressDidChange` (plus downloads/mixer equivalents).
`DiscourseLikesStore` (liked sets, optimistic toggle + rollback, pending map, 7-day `/likes` gate, counts, favourite
payloads/collections), `DiscourseHistoryStore` (max 24, newest first), `DiscourseStatsStore` (24 h `/stats` dedupe),
`DiscourseStatsCache` (weekly lists, 3 h TTL, stale-on-failure, forced network read on expiry),
`DiscoursePlaybackStore` (resume, completion, fractions, played, durations; unchanged bulk registrations do not write or notify), `DiscoursePlaybackSettings`
(`playback_history`), `DiscourseCatalogueFilterStore`, `DiscourseMediaIdentityStore` (bounded URL → identity),
`DiscourseTrackRegistry` (in-memory payload cache, 256). Identity and playback track-info indexes decode once
per store instance and remain owned by their serial queues; writes preserve the existing keys/formats. Queue creation
and continuation persist identity records in one batch, retaining the 512-entry limit.

### 4.6 Discourse UI layer (`Sources/Discourse/UI/`)

- **Discourse cards**: `DiscourseCardView` in `DiscourseCardCell` and the discourse branch of `DiscourseSearchCell` is the sole renderer for Catalogue, Home, Search and favourite discourses. A warm gradient surface with a 20 pt corner/border contains square aspect-fill artwork (20% of card width, bounded to 72–160 pt), a two-line title/chevron, language and optional city pills, and track/calendar metadata followed by download status, a divider and the heart. Cards are at least 132 pt tall and self-size; narrow cards stack footer metadata and accessibility sizes put artwork above the full-width text. Home keeps horizontal carousels with cards at 92% of the available section width. Missing/blank `location`/`date` hide their icon/pill/separator; location keeps only the trimmed first comma-separated part. ISO date-only/timestamp values preserve their calendar day and use localized abbreviated-month dates (“Jun 10, 1974” in US English); invalid dates are hidden. Download status is an indicator, retaining completed/active counts and existing targeted notifications; card taps open detail and hearts remain independent accessible actions.
- **Catalogue**: one-column list of the shared cards; cache-first paging (`page < meta.total_pages`, dedupe, guarded `insertItems`), 400 pt prefetch, force pull-to-refresh, language/sort `UIMenu` persisted in the filter store, request token drops stale answers, failures keep rendered rows.
- **Detail**: sorted tracks, header (artwork, title, optional city/date chips directly beneath the title, summary, **Play all**, heart), progress ring/speaker/checkmark, row and
  nav-bar download actions, long-press Play/Play next/Add to queue/download. Track rows keep the duration, download
  and like controls at their intrinsic width, so a long title wraps to its second line instead of compressing the
  icons into each other. Header chips reuse `DiscourseCardMetadata` and the card formatters/empty-value rules; both absent collapses the chip stack. Accessibility sizes move artwork above the full-width text. Cache reads and track sorting run off the main actor; identical track lists skip registration and table reloads.
- **Search**: `UISearchController`, 350 ms debounce, `/discourses?search=` + `/discourse-audios?search=` together,
  **Discourses** then **Tracks**, lockstep paging to the deeper endpoint, idle/spinner/results/no-match/error states.
- **Home**: `DiscourseHomeContent` builds Recently played, Recently played tracks (discourse history then library
  history via `DiscourseLocalTrack`, hidden while history is off), Top discourses this week, Top tracks this week.
  Carousel headers ignore section insets so all Home headings align at the same 16 pt leading edge.
  Local history is fetched/mapped off-main on first appearance, library history changes, or explicit refresh;
  returning to Home reuses it. Unchanged sections skip reloads; stable section order reloads only changed sections.
- **Playlist cards**: ordinary playlist rows and automatic favourite collections use 12 pt corners, track surfaces
  and track borders; list cards are at least 112 pt tall with 112 × 88 pt aspect-fill artwork and track counts; favourite cards have 8 pt spacing; favourite discourses use the shared, self-sizing discourse card. Favourites live in a non-pinned collection header and scroll with ordinary playlists.
- **Track rows**: vertically centred title and subtitle; duration comes first, and a discourse name matching the
  title (ignoring case and surrounding whitespace) is omitted. Shared by Home, search and favourite tracks.
- **Likes/downloads**: `DiscourseLikeControl` + `DiscourseLikeActions` and `DiscourseDownloadControl` +
  `DiscourseDownloadActions` are the only render/action paths; cards/rows are accessibility containers holding a
  transparent `DiscourseAccessibilityButton` and the heart; discourse cards show a download-status icon with counts such as `3/11` when active or downloaded.
  The expanded player uses a 24 pt heart with no likes and the compact 18 pt heart beside positive counts.
  Download notifications carry changed audio/discourse IDs and distinguish byte progress from state changes.
  Progress retains the 2% threshold and coalesces across tracks for 100 ms; completion/cancellation/removal publish
  immediately. Screens update only affected download controls; progress does not rebuild menus, badges, hearts, or
  favourite collections. Notifications without the payload retain the legacy full-refresh behavior.
- **Mixer screen**: wave hero (equalizer mark, **Background Music Mixer** + subtitle), track cards (artwork, title, duration, checkmark; long-press drag reorder, swipe delete), a dashed **Tap + to add an audio file** slot and a pinned panel (grabber, play/pause, **Mixer on/off** + status, Loop pill, volume with minus/plus and percentage; tapping the title/status toggles the switch). Detail rows swipe left for **Add to Playlist** (upstream picker, streaming URL + identity); the expanded player has a Like / Clip / Download / Noise row (Add to Playlist and Discourse precede Queue in the top toolbar), a circular accent play button and 30 s skips (row hidden in landscape). All fork screens observe theme/likes/downloads/progress and reconfigure only affected visible rows.

### 4.7 Discourse playback bridge (`Sources/Discourse/Playback/`)

Builds `VLCMedia`/`VLCMediaList` and calls the upstream entry point; no second player or queue type.
`DiscourseMediaFactory` maps a track: verified local download else resolved remote URL; title/artist `Osho`/album
discourse title; artwork (audio `discourse_thumbnail_url` first, discourse thumbnail fallback), track number, duration; identity via `rd.discourseID`/`rd.audioID` extras plus the
`DiscourseMediaIdentityStore` URL index (`.m3u` cannot carry extras) — always attribute with `identity(of:)`.
`DiscoursePlayback.play(tracks:discourse:startingAt:)` drops unusable URLs, applies the resume fraction to the first
item only (≥1 s, never the last 5 s, ≤0.98, never completed) and calls `playMediaList`; the one-item
`play(track:discourse:)` appends the rest of the discourse after fetching it without interrupting playback.
`playNext`/`appendToQueue` mutate both lists. `DiscoursePlaybackProgress` holds the player-free rules: accumulate
position deltas only while playing (>3 s = seek, none negative), qualify after 60 s, save every 30 s and on
pause/stop/next/fail/background, complete within 1 s of the end, clear completion on replay-from-start.
`DiscoursePlaybackTracker` observes the notifications, writes history/resume and posts `/stats` once per track per
24 h, all gated by `isHistoryEnabled`.

### 4.8 Discourse downloads (`Sources/Discourse/Downloads/`)

`DiscourseDownloadStore` keeps `Application Support/Discourses/<audioID>.audio` (backup excluded) plus two defaults
maps; `localURL(for:)` answers only for an existing non-empty file, and launch prunes vanished records and orphan
files. `DiscourseDownloadManager` runs one background `URLSession`
(`online.sandalbar.rajneesh-discourse.downloads`), three concurrent transfers, a pending queue,
`taskDescription = audioID|discourseID` for relaunch reattachment, ≤2%-step progress, and
missing/downloading/downloaded/failed states; `VLCAppDelegate` forwards background-session events. Download notifications reach `DiscoursePlaybackTracker`, which hands an actively playing remote discourse track to `VLCPlaybackService.replacePlayingMedia` once its local file is verified. Both queue orders and position are retained; paused/stopped tracks never auto-start.
A verified
download wins over streaming; single-track and whole-discourse download, cancel, remove and remove-all are supported.

### 4.8.1 Local clips

`Sources/Discourse/Clips/` owns range selection, the Export Clip drawer and AVFoundation audio/video export. The audio controller integrates the editor into the progression area and previews with the existing VLC player; no additional player or audio-session changes. Opening the editor pauses the main player. Clip eligibility accepts a restored paused track with a finite duration of at least one second before VLC opens its decoder; normal playback still requires seekability. Metadata recovery refreshes player actions, so recovered payloads enable Clip while paused and on player re-entry. Handles and VoiceOver adjustments retain a minimum one-second range. The clip panel has separate start/end minus and plus buttons (one second per tap, disabled unless a full step preserves track bounds and the one-second minimum). Dragging either bracket (including during the drag), endpoint +/− and VoiceOver adjustments, and caption phrase selection immediately move the playhead and arm the next preview. Start edits target start; end edits target max(start, end − 10 seconds). A gray full-track rail carries a red selection, slim rounded brackets and a playhead with a floating time label; labels below show 00:00 and full duration. Selected duration and a capsule Cut button sit below. The floating playhead label uses the exact supplied timestamp outside dragging, avoiding a one-second loss from the slider’s normalized Float round trip. The panel is 168 pt before Dynamic Type scaling, with endpoint controls and the footer stacked at accessibility sizes; transport width/alignment stays unchanged. Portrait artwork yields to the bottom transport constraint when the editor and metadata need more height, keeping playback controls within the safe area; clipping uses compact vertical spacing below 750 pt of player height. Play uses the position armed by the latest bracket edit or paused scrub, otherwise the start bracket; preview stops at the end bracket. Preview requests are one-shot and deferred until resumed audio advances 0.5 s; dragging suspends them. Preview uses `VLCPlaybackService.seek(toMilliseconds:)`, which sets VLCKit’s absolute time. Verified local discourse files (including restored queues) use the bundled `avformat` demuxer because native MP3 seeking on the store’s `.audio` downloads can land early or at EOF; streaming keeps its existing demuxer. Position ticks update the playhead and stop at the end, but never re-arm a seek; optimistic and stale VLC timestamps therefore cannot restart a one-second fragment. Paused bracket adjustments do not seek the native player or start playback. Clips snapshot noise cancellation and mixer settings. `DiscourseClipExportRequest` feeds a detached, cancellable renderer: AVAssetReader decodes 48 kHz stereo float blocks; a temporary CAF spool bounds memory and measures the combined peak before uniform attenuation and AVAssetWriter AAC encoding at 192 kbps. Enabled RNNoise runs first with up to one second of pre-roll, the playback engine’s 480-sample framing, a 960-sample compensated delay and tail drain. Decoding continues past the selection for sample-rate conversion, then trims at the exact 48 kHz output boundary; at EOF it allows up to 128 zero frames for the converter’s withheld tail, after validating that the source duration covers the selection. The mixer source is copied into the operation directory, starts at zero with its volume/loop setting, and is mixed after noise cancellation. Unavailable requested processing fails explicitly. Device volume and playback rate do not affect output. Create video from clip uses PHPicker (one image or video, no broad library permission); its temporary representation is copied inside the provider callback. Photos remain static; video visuals repeat/trim from zero, ignoring their soundtrack. H.264 is written at 30 fps, aspect-preserving even dimensions within landscape 1920 × 1080 or portrait 1080 × 1920 without upscaling; AVFoundation converts video colour to SDR Rec.709. Both streams end at the selected 48 kHz sample boundary. Export closed captions is off per drawer session; the existing caption loader supplies overlapping phrases, clipped/rebased/renumbered into a UTF-8 SRT with the media basename. Requested captions fail with retry/disable guidance if unavailable or empty. Media and sidecar use one Files handoff. Options stay disabled during rendering and Files handoff. Preparation, source downloading and rendering use one full-screen progress modal with themed waves, an audio waveform or video clapper icon, a percentage ring/bar and Cancel; progress never appears in both drawer rows. Cancel returns to the drawer, invalidates the operation and cleans temporary output while leaving source downloads running. The progress modal dismisses before Files opens; stale handoffs after cancellation/backgrounding are discarded. The source is reused or downloaded through the existing manager and retained. Export creates a temporary hard link (copy fallback) with the original URL extension because AVFoundation rejects the store’s `.audio` filenames; cleanup removes that link along with the output. Pending downloads report downloading at 0% while queued. Temporary `DiscourseClips/<operation>/` exports are removed after picker completion/cancel, errors, and once when the player initializes after relaunch. No new persisted defaults or backend routes.

### 4.8.2 Discourse captions

`Sources/Discourse/Captions/` owns the Foundation-only SRT parser/URLSession loader and UIKit scrolling transcript. `DiscourseAudio` decodes `has_cc`/`cc_path` with false/empty defaults for old caches; caption URLs use the existing HTTPS CDN resolver. Fetches never send the API key to the CDN, validate HTTP/UTF-8/nonempty cues, cache successful responses through URLCache and support explicit retry. Track changes cancel the request and discard late results. Restored-track payload recovery refreshes service metadata even when artwork is unchanged, enabling CC while paused. No new defaults or player instances.

The expanded player's CC action is enabled only for track-level availability plus a valid caption URL. In portrait it replaces the artwork and title/artist/discourse metadata region with a taller transcript, preserving transport. Landscape retains its separate metadata column. The transcript flows as one paragraph, joining phrase boundaries and cue-internal line breaks with spaces without changing source cues or SRT export. Existing VLC position ticks highlight the latest phrase whose SRT start has been reached; it stays highlighted through gaps until the next phrase starts. Before the first cue and after the last, the first/last phrase remains highlighted; seeks recompute this from the new position. Manual scrolling suspends following until “Follow current phrase” is tapped. Current phrase and clip-selection background are distinct. The text view supports Dynamic Type and exposes each phrase to VoiceOver with current-phrase state and clip activation; the artwork pan yields to transcript gestures.

The transcript explicitly selects TextKit 1 with `usingTextLayoutManager: false` on iOS 16+, retaining the existing initializer on iOS 15. This also matches the tap and accessibility geometry APIs. An isolated simulator harness scrolling the same real 1,428-phrase Hindi transcript while paused reproduced TextKit 2 fragment-drawing stalls at p95 777 ms; rebuilding from the fixed source measured 1.79 ms with no frames over 50 ms (16.7 ms scroll-work budget). Initial phrase styles are batched with `textStorage.beginEditing/endEditing`: applying them individually after the view is attached causes repeated full layouts and stalls opening CC. A visible-view harness with deep scrolling also passed the p95 budget for Hindi and generated English (7.05/4.19 ms paused; 2.43/1.20 ms with half-second simulated position updates). The update runs still recorded occasional frames over 50 ms (1/3 over six seconds respectively), so the renderer switch does not guarantee every phrase-change frame meets the budget. The transcript container returns nil for plain/attributed accessibility values; phrase elements remain the accessible content, avoiding UIKit converting the entire styled paragraph during accessibility snapshots. The unit regression checks `textLayoutManager == nil` immediately after view construction, before display, taps or accessibility geometry can trigger implicit fallback. The caption/clip suites (27 tests) and caption-toggle/clip-phrase-selection UI regression pass. These are simulator measurements; finger scrolling and player responsiveness on the affected iPhone remain manual acceptance.

Opening Clip automatically shows available captions and closing it restores the previous CC visibility. Start is initially active. Tapping/dragging a bracket, using its adjustment buttons or VoiceOver activates that bracket and visibly marks it selected. Tapping any word in a phrase sets the active start to phrase start or active end to phrase end, preserving the existing one-second minimum and track bounds. Selection persists until another bracket is activated; both endpoint updates reuse the preview-position callback and never start playback. Caption failures leave the clip editor usable.

### 4.9 Audio Mixer (`Sources/Discourse/Mixer/`)

`DiscourseAudioMixer` owns a **second** `VLCMediaPlayer` (VLCKit allows one per instance), created at launch, never
touching the main queue, mini player or now-playing info. Storage: `audio_mixer_files` (ordered URLs),
`audio_mixer_selected` (URL, not index), `audio_mixer_enabled` (`false`), `audio_mixer_loop` (`true`),
`audio_mixer_volume` (50, clamped 1…100); stale container paths re-root at launch. It follows the main player 250 ms
after start (audio only; video stops it), fades in ~200 ms, pauses/stops with it (~220 ms fade out), loops or stops at
track end, reloads on loop change, and its play button only arms it. Pausing from that button is an explicit off:
it clears the persisted switch (and the panel shows the disabled labels), so a later main track cannot restart the
mixer until the user presses play again. It shares the app's single `AVAudioSession` and handles interruptions,
route loss and media-services resets. `DiscourseMixerFileImporter` copies document-picker
selections into `Application Support/AudioMixer/<source-id>/`, so playback survives relaunch without a bookmark;
removal deletes only app-owned copies.

## 6. Product requirements

### 6.1 Navigation and screens

Five destinations in order: **Home**, **Discourses**, **Search**, **Playlists**, **Mixer**. Home shows, in order and
dropping empty sections: Recently played (discourses, max 24), Recently played tracks (discourse + library history,
deduped, hidden while history is off), Top discourses this week, Top tracks this week
(`/stats?by=discourse|discourse_audio&time=7_days`; `by=audio` is rejected by the deployed API). Search covers the
remote catalogue only, both discourses and tracks. Browse/Videos tabs, video browsing/settings, the shuffle FAB, the
extra file-menu items and player Incognito are gone. The system tab bar is theme-aware with the discourse accent (iOS
26 floating capsule, classic bar on 15–18, iPad sidebar), and the mini player floats above it without overlapping.

### 6.2 Discourse API integration

Base `https://oshoapi-0i8tq.bunny.run/`, `x-api-key` on every request, JSON, snake_case fields matching `api/docs.md`
and `api/types/discourse.type.ts`. Request timeout 15 s, resource timeout 30 s, no waiting for connectivity. GETs
cache 24 h except `/likes`; stale cache serves on transport/5xx failure; force refresh sends `Cache-Control:
no-cache`; errors never erase rendered content. Relative media URLs resolve against `https://osho.b-cdn.net/OSHO/`;
non-HTTPS is rejected. Error copy: "Failed to communicate with the server."; like failure: "Could not update your
like. Tap the heart to try again."

### 6.3 Playback and queue behaviour

Starting one track builds a queue continuing with the rest of its discourse; a single known track appends the full
list after fetching it, without interrupting playback. Index `n` continues at `n+1`. Mapping and resume rules are in
§4.7. Position saves on pause/stop/next/media change/background and every 30 s, restores when the item starts,
completes at the end and clears on replay-from-start. A play qualifies for history/stats after **60 s of actual
playback** (pauses, buffering and seeks excluded); previous/next count. A scrub-bar seek captures the chosen time at
gesture time, holds the thumb and elapsed label until the player reports that time (or a timeout), and seeks audio by
absolute timestamp because a streaming duration estimate can make the 0…1 position land elsewhere; later position
updates therefore cannot re-apply the pre-seek time.

### 6.4 Likes

Anonymous UUID identity; liked ID sets plus a last-fetch timestamp; `GET /likes` at most every **7 days** on
launch/foreground. Optimistic toggles with rollback and persisted pending targets; discourse and track likes are
independent. Successful responses cannot reverse an optimistic count change (like uses the larger total, unlike the smaller); concurrent or already-recorded server changes can therefore differ from the displayed session count. Confirmed mutation counts take precedence over cached list payloads for the current session (other users’ changes
may remain unseen until relaunch). Counts format `999`/`1.2k`/`1m`. Liked heart `#FF5269`, unliked outline `#BEA8AA`. Labels "Like {title}.
{n} likes" / "Unlike {title}. {n} likes". Automatic **Favourite Tracks** / **Favourite Discourses** collections appear
above ordinary playlists (and suppress the playlist empty-state logo/text) only while they contain a like whose saved payload can be rendered; the final unlike (or a
like with no payload) hides the row and its reserved space.

### 6.5 Listening stats and history

Recently played tracks/discourses, each max 24, deduped. `POST /stats` once per track per 24 h, marked only after
success. Weekly lists cache 3 h and force-refresh on expiry. The `playback_history` setting (Settings → Playback,
default on) gates history, stats and Home's track-history section.

### 6.6 Downloads

Background `URLSession`; single-track and whole-discourse download; per-track progress and per-discourse counts;
missing/downloading/downloaded/failed; green tick; play locally only when verified; cancel/remove/remove all (confirm
"Remove all downloaded tracks from this discourse?"); no orphan files; report a repeated failure once.

### 6.6.1 Clip Share

Discourse tracks with a finite seekable duration of at least one second expose Clip next to Noise Cancellation. Tapping Clip first checks for a verified local source. Otherwise show “You must download the track to cut the clip.” with a Download button and close icon; Download starts or joins the normal background download, while Close leaves the editor closed. Tap Clip again after completion to edit. The player reuses the track-card download control, including progress, cancel/retry/remove actions and green downloaded state, and observes download changes. Removing the source exits editing. Add to Playlist moves into the top toolbar immediately before Discourse. Selection begins at the current position and ends 10 minutes later, bounded by duration; at the end, move the start back to preserve one second. Handles cannot cross; 10 minutes is only a default. Play previews the selection; seeks clamp into the range and preview pauses at its end without modifying repeat settings. Track changes or closing the player leave editing. Cut pauses and opens the large, scrollable Export Clip drawer with artwork, title, selected range, a settings card, independent Fade in (2 seconds) / Fade out (2 seconds) switches (both initially on), and Share clip link (subtitle “Share clip link with anyone”), Download clip audio and Create video from clip (subtitle “Select video or photo”). Noise cancellation and Background music reflect and immediately update their existing live owners and observe external changes. Unavailable noise cancellation is disabled; missing mixer sources disable Background music with “Add music in Mixer first”. Export closed captions is always visible, initially off and enabled only for a valid caption source; otherwise it shows “Not available for this track”. No export folder or new persisted preferences. Create video from clip opens a native ratio menu on every attempt: Default (Original ratio) is checked, followed by 9:16 — Mobile and 16:9 — Desktop. Selection snapshots ratio and processing settings before Photos opens; menu dismissal and picker cancellation leave the drawer idle. Original rendering is preserved. Fixed ratios center crop displayed photo/video orientation without stretching or borders, using even multiples of 18 × 32 or 32 × 18 capped at 1080 × 1920 or 1920 × 1080; only sources smaller than one unit are upscaled. Ratio is not persisted and affects only video. Processing settings and fade choices are captured before asynchronous visual/source preparation. Linear fades apply after peak attenuation to the combined speech/music soundtrack in both M4A and MP4, without changing visuals, clip duration or SRT timing. Each fade is at most two seconds, bounded by half the duration when both enabled or the full duration when only one enabled. Other export callers default to no fades. Link sharing opens the system share sheet with the track title and `https://rajneeshdiscourse.com/discourses/{discourseID}/tracks/{audioID}?start={seconds}&end={seconds}`; endpoints preserve fractional seconds and whole seconds have no decimal suffix. Export waits for a verified full source, renders enabled processing locally to AAC/M4A or H.264/MP4 with optional SRT, and opens Save to Files. Failures support retry; cancel leaves source downloads running. Export is foreground-only and cancels on background. Hardware timing and Files acceptance remain manual checks.

### 6.7 Audio Mixer

A second player for explicitly added local files only; order, selection and switches persisted;
add/remove/reorder/clear. Defaults off, loop on, volume 50 (1…100). Follows the main player (audio only),
pauses/resumes/stops with it, stops on video, loops at the end when asked, fades in/out; volume never resets. The
play/pause button is also the user's off switch: pausing clears `audio_mixer_enabled`, so the mixer stays off for
later tracks and relaunches until the user presses play (or the on/off toggle). One shared audio session;
interruptions, route changes and media-services resets pause both and restore mixer state. **Clear all** confirms
before deleting.

### 6.8 Design system

Dark burgundy/near-black palette with warm surfaces and red accents, plus a light equivalent; dark is first-launch
default. Exact brief tokens: Accent, App background, Detail background, Surface, Border, Primary/Secondary text,
Divider, Liked/Unliked heart, Downloaded, Audio Mixer and Mini player palettes. Corners 8 pt (thumbnails), 8–16 pt
(cards), 16 pt (mixer panel); artwork aspect-fill with rounded corners; controls theme-aware, never black on dark.
Implemented as `DiscourseColors` (§4.1).

### 6.9 Branding and About

Display name, onboarding, About, prompts, empty states, notifications and widgets say **Rajneesh Discourse**;
launcher/onboarding/header artwork is branded (header mark 8 pt rounded). About says: *"Rajneesh Discourse is a local
media player distributed by Sandalbar Enterprises, Inc. It is built from open-source software; upstream authors and
licenses are listed below."* Help links point to <https://rajneeshdiscourse.com>; upstream feedback links are removed;
licence acknowledgements stay.

## 7. Local persistence contract

All fork keys keep the brief's names (`osho_api_*`, `audio_mixer_*`). Decode defensively (corrupt JSON = empty, never
crash); writes are synchronous/serialised; never store the key, the UUID in logs, or tokens world-readable.

| Key | Type | Owner |
|---|---|---|
| `osho_api_user_id` + keychain `online.sandalbar.rajneesh-discourse.identity` | UUID / password | `DiscourseIdentity` |
| `osho_api_liked_{discourses,audios}`, `osho_api_likes_fetched_at`, `osho_api_likes_pending` | sets / epoch / JSON | `DiscourseLikesStore` |
| `osho_api_favourite_metadata` | JSON payloads, dates, unavailable, created | `DiscourseLikesStore` |
| `osho_api_recently_played_{discourses,audios}` | JSON, max 24 | `DiscourseHistoryStore` |
| `osho_api_catalogue_{language,sort}` | `String?` | `DiscourseCatalogueFilterStore` |
| `osho_api_stats_{discourses,audios}` (+`.time`) | JSON + epoch | `DiscourseStatsCache` |
| `osho_api_discourse_playback_position.<audioId>` | ms | `DiscoursePlaybackStore` |
| `osho_api_discourse_{completed,played}_audios` | `[String]` | `DiscoursePlaybackStore` |
| `osho_api_discourse_track_info` | JSON `[audioId: {discourseID, durationMilliseconds}]` | `DiscoursePlaybackStore` |
| `osho_api_stats_sent` | JSON `[audioId: epoch]` | `DiscourseStatsStore` |
| `osho_api_discourse_media_identity` | JSON URL → identity (512) | `DiscourseMediaIdentityStore` |
| `osho_api_discourse_downloads`, `…_download_discourses` | JSON maps | `DiscourseDownloadStore` |
| `playback_history` | `Bool` (absent = true) | `DiscoursePlaybackSettings` |
| `audio_mixer_files/_selected/_enabled/_loop/_volume` | URLs / URL / bool / bool / int | `DiscourseAudioMixer` |
| `PlaybackSnapshot.json` | versioned snapshot | `VLCPlaybackService` (§4.2) |
| Clip exports | temporary `DiscourseClips/` files, cleaned after export workflow / relaunch | clip exporter |
| Downloads / mixer imports | Application Support files | download store / file importer |
| Caption responses | URLSession URLCache, opportunistic/evictable; not guaranteed offline | caption loader |
| API responses | `Caches/DiscourseAPI/*.json` (10 MB) | `DiscourseAPICache` |

`DiscourseTrackRegistry` is the one in-memory exception (never persisted; a restored queue fetches its payload once).

## 10. Known gaps and intentional deviations

- **App Review cleanup.** Retired integrations are excluded from iOS binaries rather than merely hidden in navigation.
  Video playback UI, PiP and external video scenes are also excluded; shared engine types remain in VLCKit.
  The cleanup alone does not establish the cause of Apple's rejection or
  guarantee approval. Confirm the submitted Release archive and metadata before resubmission.
- **Captions.** Current SRT sources contain phrase timing, so playback highlights whole phrases and clip taps use phrase boundaries regardless of the word tapped. No estimated word timing. Captions are opportunistically cached separately from audio downloads. Physical-device caption scrolling responsiveness, synchronization, VoiceOver and bracket-selection acceptance remain manual.

1. **Architecture.** Android's `PlaybackService`/`DownloadManager`/`SharedPreferences` become `VLCPlaybackService`/`URLSession`/`UserDefaults` + Keychain; `osho_api_*` names are kept.
2. **Crash reporting.** No Sentry/Crashlytics; `DiscourseDiagnostics` + `APLog` log context without secrets; expected offline/cancel/4xx are not errors.
3. **Downloads.** Background `URLSession` + app-private files, no system UI; states match the brief.
4. **Mixer.** A dedicated second `VLCMediaPlayer` (one per VLCKit instance) coordinated by notifications.
5. **Identity.** Keychain via XKKeychain plus a defaults mirror, not Keystore.
6. **Likes.** The full current contract (`GET /likes`, unlike) is implemented even where Android predates it.
7. **Settings entry point.** Modal bar button, not a tab.
8. **Tests need watchOS.** The test schemes build the watch-embedded host; the no-watch scheme has no test target.
9. **Branding artwork.** Launcher, launch screen, About, settings button, empty state and watch/tvOS art are branded; onboarding, passcode and donation cones remain upstream; `VLC26*.icon` bundles are unselected.
10. **Branding scope.** Navigation is complete; only artwork remains (item 9).
11. **HTTP timeouts.** One 15 s request + 30 s resource timeout, `waitsForConnectivity = false`; no connect timeout.
12. **Response cache.** A custom on-disk policy (24 h, stale-on-failure, 10 MB, `/likes` excluded) because the backend sends no cache headers.
13. **Page size.** The API returns 24 rows/page with no `page_size`; paginate with `page`/`meta.total_pages` only.
14. **Identity storage.** Talks to `XKKeychainGenericPasswordItem` directly with a fork-specific service id.
15. **Progress keys.** Documented per-track positions plus one JSON track-info index and completion sets.
16. **Likes cache shape.** Counts live in memory for optimistic display; a refresh clears pending toggles at once.
17. **Local library entry point.** No Discourse/Local switch; the library is pushed above the catalogue and the mixer imports through the file picker.
18. **Tab bar.** System bar, default mode on iPhone, `.tabSidebar` on iPad, accent tint, floating-bar inset; playlist cells remain upstream XIBs.
19. **Podcasts/On Air.** The surface is removed, so podcast URLs report an error; the background refresher and its background modes are gone (finite background tasks are unaffected).
20. **Card downloads are status indicators.** The shared footer always shows the download icon, adding completed/active counts when present; download actions remain in detail. Home, Catalogue, Search and favourite-discourse cards share the same self-sizing presentation.
21. **Catalogue bar-button tint.** Settings/filter buttons inherit the upstream orange `tintColor`.
22. **Duration hint.** `duration_seconds` goes to `VLCMedia.length`; libvlc replaces it with the stream length.
23. **Track identity.** Meta extras plus a bounded URL → identity index for restored queues; use `identity(of:)`.
24. **Full player on play.** Starting a track presents the full-screen player; the mini player follows dismissal.
25. **Mini-player inset.** Rows grow their inset when the mini player is shown, after the full player closes.
26. **Row actions.** Long-press context menus, not a second ellipsis affordance.
27. **Search covers tracks.** Both endpoints with unlimited paging (Android searches discourses only, capped at 24).
28. **Search paging is lockstep.** One page number for both; sections collapse; a failed next page keeps rows.
29. **Home merges histories.** Discourse history leads, library history follows (no interleave; shared cap 24).
30. **`playback_history` is fork-only**, registered in `VLCAppDelegate`, the Settings model and `Settings.bundle`.
31. **Weekly stats bypass the 24 h cache** through `DiscourseStatsService.forceRefresh:` on TTL expiry.
32. **Progress is notification glue** (`DiscoursePlaybackTracker`); resume applies only to the first queue item.
33. **The player heart needs a payload**; a restored queue without registry metadata hides it until fetched.
34. **Cards/rows are accessibility containers**, keeping the heart focusable.
35. **Card download badge** (see 20); detail rows own the per-discourse download actions.
36. **Download arrows toggle removal** when complete; remove-all confirms; detail cards use 14 pt vertical padding.
37. **Failed downloads report once** through their icon, never an alert; force quit cancels with no partial file.
38. **Mixer selection is a URL**, so reordering cannot select the wrong track; a missing selection falls back.
39. **Mixer rows show file names**, because only URLs are persisted.
40. **End of track is `.stopped`** in VLCKit 4; the mixer flags requested stops.
41. **The mixer never plays standalone**; its play button only arms it.
42. **Video detection** uses `numberOfVideoTracks`/`playAsAudio`.
43. **Clear all confirms**, matching the destructive-action pattern.
44. **RNNoise needs the custom engine**; bypassed audio costs ~20 ms latency and CPU; device acceptance is pending.
45. **Watch identifiers.** `com.oshodiscourse.watchos` names the app as companion; signed builds need a team profile.
46. **Deep links are Universal Links.** No fetch-by-id route: metadata is rebuilt from history/registry, then a catalogue search, then the track list; deploy the AASA.
47. **Donation nag removed** (gate, controller, XIB, strings); onboarding and donation support remain.
48. **Local audio access is folder-scoped**; no system permission status exists.
49. **Local library pager is pinned** to the Songs page; the upstream index still writes for other hosts.
50. **Mixer imports are app-owned copies**; removing a row deletes only that copy.
51. **Optional permissions removed** (alarm, biometrics, photo saving, iCloud Documents); Local Network is the only prompt and the `NSUbiquitousKeyValueStore` entitlement stays for other services.

52. **Clip Share** exports processed audio as M4A or photo/video visuals as MP4 with an optional SRT sidecar through Files; Share clip link shares the track title and public URL with selected start/end seconds. Incoming iOS links still open/highlight the track without applying the query range. Export cancels on background. Automated clip/caption tests pass on the simulator (27) and iPhone 14 Pro/iOS 26.6.1 (22, excluding the existing `testPanelLayoutsAndPlayhead` bounds assertion, which fails on that device). Generated-fixture orientation, looping/trimming, soundtrack removal and processing checks passed on the phone. Video ratio fixtures additionally cover original, 9:16 and 16:9 outputs from portrait/landscape/square photos, EXIF orientation, rotated video tracks and large-source size caps on the simulator, checking centered markers, proportions, border-free output, duration and soundtrack fades. Ratio-menu VoiceOver and physical iPad acceptance remain manual. The simulator clip UI regression passes the redesigned drawer actions, export-progress cancellation, video-picker cancellation, processed-audio saving through Files and unchanged link sharing. Decoded M4A/MP4 fixtures verify all four fade combinations on one- and six-second clips with background music; drawer snapshots cover dark/light and narrow/accessibility layouts. Physical-device listening/preview timing, Files handoff, iCloud-only picker items, HDR tone mapping and export synchronization still need manual acceptance. Offline noise cancellation resolves the pinned RNNoise C functions exported by custom VLCKit; binaries lacking these functions report an actionable error.

Add new deviations here as they are found; never hide a gap.

## 11. Upstream sync policy

This fork tracks VLC for iOS `master`. Keep fork code in named files/directories (`Sources/Discourse/`, `Discourse*`
types) and upstream edits small and listed here. Merge by rebasing/cherry-picking onto `master`, preserve fork
behaviour on conflicts, re-run `pod install`, rebuild, re-run [AGENTS.md §8](../AGENTS.md#8-testing-and-verification) and update [AGENTS.md §9](../AGENTS.md#9-current-status) / §10. Never let a sync drop the rebrand,
the five tabs, the dark default, the discourse/mixer layers, paused snapshot restoration, automatic favourite
collections or the removal of retired iOS integrations, Google Drive/OneDrive and optional permissions.

Fork touch points (upstream files we intentionally edit):

- `Sources/Playback/Control/VLCPlaybackService.{h,m}` and `VLCPlaybackService+MediaLibrary.m` — RNNoise switching,
  audio session, snapshot hooks, asynchronous periodic checkpoints with cached queue metadata, paused retention,
  absolute-time clip seeking and iOS audio-only engine options/PiP removal.
- `Sources/Playback/Control/VLCPlayerDisplayController.{h,m}`, `Sources/Playback/Queue/QueueViewController.swift`,
  audio player, `PlayerController`, `PlayerInfoView`, navigation bar and `UIStackView+Orientation.m` — audio-only
  presentation/queue callbacks, no external video display, PiP or 360-degree motion on iOS; shared audio controls stay.
  `Sources/ShareExtension/Info.plist` — no movie activation; iOS Info.plist removes external scenes/cloud query schemes.
- `Sources/Playback/OS Integration/VLCMetadata.m` — iOS metadata always identifies the main session as audio.
- `Sources/Playback/Player/` — `PlayerViewController`, `AudioPlayerViewController`, `VideoPlayerViewController`,
  `AudioPlayerView`, `MediaMoreOptionsActionSheet` + subviews, `ActionSheetCell`: white spinner, noise switch, discourse heart, targeted player download updates, Share row, Clip editor integration, 168 pt Dynamic Type-scaled height and the scrub bar's captured seek intent with absolute audio seeks; restored-paused Clip eligibility and metadata-driven action refresh; CC action, portrait transcript artwork/metadata replacement and active clip-bracket caption selection.
- `Sources/App/iOS/TabBarCoordinator.swift` — five tabs, index, accent, bar modes, local library, album/deep links,
  tracker/mixer startup, likes refresh. `VLCAppDelegate.m` — defaults, background downloads, web-activity links.
  `Sources/App/VLCAppCoordinator.{h,m}`, `VLCAppSceneDelegate.m` — registration, deferred links, restoration.
- `Sources/App/VLCAppCoordinator.{h,m}` — iOS omits upstream network/cloud/subscription/donation services;
  `VLCAppDelegate.m` and watch session delegate omit legacy Transfers reporting; OS remote commands remain.
  `Sources/Helpers/Network/URLHandler.swift` — iOS accepts local media/playlist files only; other platform handlers
  are compiled separately. `Sources/CarPlay/VLCCarPlaySceneDelegate.m` — library/playlists without On Air.
  `Sources/App/iOS/AppShortcuts.swift`, `MediaLibraryModel/MediaModel.swift` — removed radio/video intent exposure.
  `Sources/Helpers/ColorThemeExtension.swift`, bridging header and player display controller — removed retired
  screen imports, transfer banners and presentation. Player navigation omits upstream radio favourites.
- Entitlements (`Resources/iOS/VLC*.entitlements`) — Associated Domains, removed caches.
- `Sources/Discourse/DeepLink/` + `Buildsystem/DeepLinks/` — parser, share URL, tests, AASA.
- `Sources/Media Library/` — playlist accent/artwork/rounded thumbnails/favourite rows (`PlaylistViewController`,
  `CollectionArtworkHeader`, `PlaylistModel`, `MediaCollectionViewCell`, `MediaGridCollectionCell`,
  `CollectionInfoFooter`, `MediaCategory`); self-sizing favourite discourse cards, scrolling favourite header; targeted favourite-row download updates; **Add to Audio Mixer** and local-library empty state (`MediaCategoryViewController`);
  branded empty state (`VLCEmptyLibraryView`, `MediaViewController`).
- `Sources/Settings/{Model/SettingsSection.swift,Controller/SettingsController.swift,View/SettingsCell.swift}` and
  `Resources/iOS/Settings.bundle/*` — playback history, removed video/subtitle/podcast/network rows and Transfers.
- `Sources/Media Library/MediaLibraryService.swift` — iOS omits subscription caching; local artwork caching stays.
- `Sources/UI Elements/Buttons/AppMenuBarButtonItem.swift`, `Sources/About/*`, `Sources/Onboarding/*`,
  `Resources/en.lproj/Localizable.strings` — branding, About, contact, empty-state copy.
- `Resources/iOS/{Info.plist,Launch Screen.storyboard}`, `Buildsystem/SharedConfig.xcconfig`, app/watch/tvOS asset
  bundles, `Sources/Headers/VLCConstants.h`, `Sources/UI Elements/PresentationTheme.swift` — name, dark default,
  palette, artwork.
- `Sources/Headers/VLC-iOS-Bridging-Header.h` — `DiscourseSecrets.h`, `VLCNetworkImageView.h`.
- Mini-player/queue display files — mini-player notifications, artwork sensor, queue metadata.
- `VLC.xcodeproj/project.pbxproj` — secrets phase, header search paths, file registration.
- New fork-only folders: `Sources/Discourse/{API,Stores,Playback,Downloads,Mixer,UI,DeepLink,Captions}`,
  `Buildsystem/{RNNoise,DeepLinks,Testing}`.
