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
  `DiscourseAudioMixerViewController` (`AUDIO_MIXER`, shown as **Mixer**). `VideoViewController`,
  `VLCServerListViewController` and `VLCOnAirViewController` remain for upstream sync but have no surface.
- Selected index persists as `TabBarIndex` (0…4). iPhone keeps the system tab bar (iOS 26 Liquid Glass capsule;
  `.tabSidebar` is iPad only) and tints the selected item with the discourse accent; fork scroll views add
  `discourseFloatingTabBarInset` on iOS 26.
- Settings is modal from `AppMenuBarButtonItem` (**About Rajneesh Discourse** + **Settings**); Home uses a static logo
  with a right-hand chevron dropdown. Home, Search and Mixer share `DiscourseScreenViewController` and
  `DiscourseEmptyStateView`; Home and Mixer have no navigation title, the catalogue owns its collection view.
- The device library is not a tab: `DiscourseLocalLibraryViewController` (an `AudioViewController` reduced to Songs +
  Folders) is pushed above the catalogue by `TabBarCoordinator.showLocalLibrary(pushing:)`.
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
- Mini player: `VLCPlayerDisplayController` + `VLCAudioMiniPlayer`. Full player: `AudioPlayerViewController`
  (discourse heart before more-options; Share row for a discourse track) and `VideoPlayerViewController`; buffering is
  a plain white spinner. The player’s Discourse header action uses the current media identity’s `discourse_id` and
  remains enabled while the full track payload is being fetched. Disabled Clip and Download controls stay white
  in both themes for contrast. Expanded audio artwork swipes horizontally: left = Next, right = Previous (commit
  at ¼ width or 500 pt/s; Reduce Motion uses a cut).
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
  The mixer never auto-starts.

### 4.3 Library, networking and storage

- Library: VLCMediaLibraryKit (`VLCMediaLibrary`, `VLCMLMedia`, `VLCMLPlaylist`, …) over SQLite in
  `Library/MediaLibrary/`; `MediaLibraryService` is the only entry point (setup, fetch, playlists, playback state,
  `MediaLibraryObserver`). iOS has no global audio permission: access is per external folder via the document picker
  (`addExternalFolder(at:)`); the Local Songs empty state distinguishes "No files found" from "add a folder".
- HTTP: `VLCHTTPClient` (NSURLSession + JSON), `VLCTransferController`, `VLCThumbnailsCache`/`VLCNetworkImageView`,
  Firebase Analytics (needs gitignored `Resources/iOS/GoogleService-Info.plist`). **No crash SDK**: `APLog` and
  `DiscourseDiagnostics` only.
- Settings are `NSUserDefaults` keys in `VLCConstants.h` (registered in `VLCAppDelegate`). Keychain via
  `KeychainCoordinator`/XKKeychain (services `org.videolan.vlc-ios.{passcode,parentalControl}`,
  `online.sandalbar.rajneesh-discourse.identity`). Files: `Favorites.plist`, `Radio.plist`, last-played `.m3u`,
  snapshot, downloads, mixer imports.
- About: `AboutController` + `iOS/About Contents.html` (branded icon, site link, `support@marfells.com`). Launch
  screen: branded tile on `#0D0D0D`. Settings model: `Sources/Settings/Model/SettingsSection.swift` plus
  `Settings.bundle`. Localisation: `NSLocalizedString` over `Resources/<lang>.lproj`, new strings in `en.lproj`.
- Pinned: local RNNoise VLCKit (patched `4.0.0-a25`); SPM VLCMediaLibraryKit `0.15.0-b2`, XKKeychain `1.0.3`, pcloud
  `3.2.3`, CocoaHTTPServer `2.4.2`, InAppSettingsKit `3.7.1`, OBSlider `1.1.3`, GRKArrayDiff `1.1.2`, MarqueeLabel
  `4.5.3`; Pods box/ObjectiveDropboxOfficial.

### 4.4 Discourse API layer (`Sources/Discourse/API/`)

Foundation-only so models, resolver and cache test without the app. `DiscourseAPIClient` sends
`x-api-key: RD_API_KEY` to `RD_API_BASE_URL`: `discourses`, `discourse-audios`, `discourseTracks`, `likes`,
like/unlike, `stats`, `discourseStats`, `audioStats`, plus SWR readers `cached*`. Fresh GETs (24 h) come from
`DiscourseAPICache`; force refresh sends `Cache-Control: no-cache`; `/likes` is never cached; cancellation is
`.cancelled` and never serves cache; transport/5xx failures serve stale payloads. Catalogue, detail, search and Home
render any cached payload first and revalidate (SWR). `DiscourseModels` mirrors `api/types/discourse.type.ts`;
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
`DiscoursePlaybackStore` (resume, completion, fractions, played, durations), `DiscoursePlaybackSettings`
(`playback_history`), `DiscourseCatalogueFilterStore`, `DiscourseMediaIdentityStore` (bounded URL → identity),
`DiscourseTrackRegistry` (in-memory payload cache, 256).

### 4.6 Discourse UI layer (`Sources/Discourse/UI/`)

- **Catalogue**: one-column list of `DiscourseCardCell` (`.list`, 112 × 88 pt aspect-fill artwork, two-line title, language, track
  count, download badge, heart); cache-first paging (`page < meta.total_pages`, dedupe, guarded `insertItems`),
  400 pt prefetch, force pull-to-refresh, language/sort `UIMenu` persisted in the filter store, request token drops
  stale answers, failures keep rendered rows. Home reuses the cell in `.tile` layout (160 pt).
- **Detail**: sorted tracks, header (artwork, summary, **Play all**, heart), progress ring/speaker/checkmark, row and
  nav-bar download actions, long-press Play/Play next/Add to queue/download.
- **Search**: `UISearchController`, 350 ms debounce, `/discourses?search=` + `/discourse-audios?search=` together,
  **Discourses** then **Tracks**, lockstep paging to the deeper endpoint, idle/spinner/results/no-match/error states.
- **Home**: `DiscourseHomeContent` builds Recently played, Recently played tracks (discourse history then library
  history via `DiscourseLocalTrack`, hidden while history is off), Top discourses this week, Top tracks this week.
  Carousel headers ignore section insets so all Home headings align at the same 16 pt leading edge.
- **Playlist cards**: ordinary playlist rows and automatic favourite collections use 12 pt corners, track surfaces
  and track borders; list cards are at least 112 pt tall with 112 × 88 pt aspect-fill artwork and track counts; favourite cards have 8 pt spacing.
- **Track rows**: vertically centred title and subtitle; duration comes first, and a discourse name matching the
  title (ignoring case and surrounding whitespace) is omitted. Shared by Home, search and favourite tracks.
- **Likes/downloads**: `DiscourseLikeControl` + `DiscourseLikeActions` and `DiscourseDownloadControl` +
  `DiscourseDownloadActions` are the only render/action paths; cards/rows are accessibility containers holding a
  transparent `DiscourseAccessibilityButton` and the heart; catalogue cards show a `3/11` download badge.
  The expanded player uses a 24 pt heart with no likes and the compact 18 pt heart beside positive counts.
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

`Sources/Discourse/Clips/` owns range selection, the Save Clip drawer and AVFoundation M4A export. The audio controller integrates the editor into the progression area and previews with the existing VLC player; no additional player or audio-session changes. Opening the editor pauses the main player. Handles and VoiceOver adjustments retain a minimum one-second range. The clip panel has separate start/end minus and plus buttons (one second per tap, disabled unless a full step preserves track bounds and the one-second minimum). Start adjustments use the bracket preview callback; end adjustments only change the endpoint. A gray full-track rail carries a red selection, slim rounded brackets and a playhead with a floating time label; labels below show 00:00 and full duration. Selected duration and a capsule Cut button sit below. The panel is 168 pt before Dynamic Type scaling, with endpoint controls and the footer stacked at accessibility sizes; transport width/alignment stays unchanged. Portrait artwork yields to the bottom transport constraint when the editor and metadata need more height, keeping playback controls within the safe area; clipping uses compact vertical spacing below 750 pt of player height. Preview plays from the start bracket, stops at the end bracket and restarts from the start on Play (a deliberate paused scrub supplies its own start). Start requests are one-shot and deferred until resumed audio advances 0.5 s; dragging suspends them. Preview uses `VLCPlaybackService.seek(toMilliseconds:)`, which sets VLCKit’s absolute time. Verified local discourse files (including restored queues) use the bundled `avformat` demuxer because native MP3 seeking on the store’s `.audio` downloads can land early or at EOF; streaming keeps its existing demuxer. Position ticks update the playhead and stop at the end, but never re-arm a seek; optimistic and stale VLC timestamps therefore cannot restart a one-second fragment. Paused bracket adjustments do not seek the native player or start playback. Clips use original source audio, without mixer or noise processing. The source is reused or downloaded through the existing manager and retained. Export creates a temporary hard link (copy fallback) with the original URL extension because AVFoundation rejects the store’s `.audio` filenames; cleanup removes that link along with the output. Pending downloads report downloading at 0% while queued. Temporary `DiscourseClips/<operation>/` exports are removed after picker completion/cancel, errors, and once when the player initializes after relaunch. No new persisted defaults or backend routes.

### 4.9 Audio Mixer (`Sources/Discourse/Mixer/`)

`DiscourseAudioMixer` owns a **second** `VLCMediaPlayer` (VLCKit allows one per instance), created at launch, never
touching the main queue, mini player or now-playing info. Storage: `audio_mixer_files` (ordered URLs),
`audio_mixer_selected` (URL, not index), `audio_mixer_enabled` (`false`), `audio_mixer_loop` (`true`),
`audio_mixer_volume` (50, clamped 1…100); stale container paths re-root at launch. It follows the main player 250 ms
after start (audio only; video stops it), fades in ~200 ms, pauses/stops with it (~220 ms fade out), loops or stops at
track end, reloads on loop change, and its play button only arms it. It shares the app's single `AVAudioSession` and
handles interruptions, route loss and media-services resets. `DiscourseMixerFileImporter` copies document-picker
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
playback** (pauses, buffering and seeks excluded); previous/next count.

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

Discourse tracks with a finite seekable duration of at least one second expose Clip next to Noise Cancellation. Tapping Clip first checks for a verified local source. Otherwise show “You must download the track to cut the clip.” with a Download button and close icon; Download starts or joins the normal background download, while Close leaves the editor closed. Tap Clip again after completion to edit. The player reuses the track-card download control, including progress, cancel/retry/remove actions and green downloaded state, and observes download changes. Removing the source exits editing. Add to Playlist moves into the top toolbar immediately before Discourse. Selection begins at the current position and ends 60 seconds later, bounded by duration; at the end, move the start back to preserve one second. Handles cannot cross; 60 seconds is only a default. Play previews the selection; seeks clamp into the range and preview pauses at its end without modifying repeat settings. Track changes or closing the player leave editing. Cut pauses and opens Save Clip with Share Link to Track (subtitle “Share clip link with anyone”) and Download Clip. Link sharing opens the system share sheet with the track title and `https://rajneeshdiscourse.com/discourses/{discourseID}/tracks/{audioID}?start={seconds}&end={seconds}`; endpoints preserve fractional seconds and whole seconds have no decimal suffix. Export waits for a verified full source, cuts locally to AAC/M4A, and opens Save to Files. Failures support retry; cancel leaves source downloads running. Export is foreground-only and cancels on background. Hardware timing and Files acceptance remain manual checks.

### 6.7 Audio Mixer

A second player for explicitly added local files only; order, selection and switches persisted;
add/remove/reorder/clear. Defaults off, loop on, volume 50 (1…100). Follows the main player (audio only),
pauses/resumes/stops with it, stops on video, loops at the end when asked, fades in/out; volume never resets. One
shared audio session; interruptions, route changes and media-services resets pause both and restore mixer state.
**Clear all** confirms before deleting.

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
| API responses | `Caches/DiscourseAPI/*.json` (10 MB) | `DiscourseAPICache` |

`DiscourseTrackRegistry` is the one in-memory exception (never persisted; a restored queue fetches its payload once).

## 10. Known gaps and intentional deviations

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
20. **Card downloads are a badge.** A `3/11` pill over Home tiles and in the catalogue footer (fixed-height carousel).
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

52. **Clip Share** exports original audio as M4A through Files; Share Link to Track shares the track title and public URL with selected start/end seconds. Incoming iOS links still open/highlight the track without applying the query range. Export cancels on background. Physical-device preview timing and Files acceptance remain pending.

Add new deviations here as they are found; never hide a gap.

## 11. Upstream sync policy

This fork tracks VLC for iOS `master`. Keep fork code in named files/directories (`Sources/Discourse/`, `Discourse*`
types) and upstream edits small and listed here. Merge by rebasing/cherry-picking onto `master`, preserve fork
behaviour on conflicts, re-run `pod install`, rebuild, re-run [AGENTS.md §8](../AGENTS.md#8-testing-and-verification) and update [AGENTS.md §9](../AGENTS.md#9-current-status) / §10. Never let a sync drop the rebrand,
the five tabs, the dark default, the discourse/mixer layers, paused snapshot restoration, automatic favourite
collections or the removal of Google Drive/OneDrive/optional permissions.

Fork touch points (upstream files we intentionally edit):

- `Sources/Playback/Control/VLCPlaybackService.{h,m}` and `VLCPlaybackService+MediaLibrary.m` — RNNoise switching,
  audio session, snapshot hooks, paused retention and absolute-time clip seeking.
- `Sources/Playback/Player/` — `PlayerViewController`, `AudioPlayerViewController`, `VideoPlayerViewController`,
  `AudioPlayerView`, `MediaMoreOptionsActionSheet` + subviews, `ActionSheetCell`: white spinner, noise switch, discourse heart, Share row, Clip editor integration and 168 pt Dynamic Type-scaled height.
- `Sources/App/iOS/TabBarCoordinator.swift` — five tabs, index, accent, bar modes, local library, album/deep links,
  tracker/mixer startup, likes refresh. `VLCAppDelegate.m` — defaults, background downloads, web-activity links.
  `Sources/App/VLCAppCoordinator.{h,m}`, `VLCAppSceneDelegate.m` — registration, deferred links, restoration.
- Entitlements (`Resources/iOS/VLC*.entitlements`) — Associated Domains, removed caches.
- `Sources/Discourse/DeepLink/` + `Buildsystem/DeepLinks/` — parser, share URL, tests, AASA.
- `Sources/Media Library/` — playlist accent/artwork/rounded thumbnails/favourite rows (`PlaylistViewController`,
  `CollectionArtworkHeader`, `PlaylistModel`, `MediaCollectionViewCell`, `MediaGridCollectionCell`,
  `CollectionInfoFooter`); **Add to Audio Mixer** and local-library empty state (`MediaCategoryViewController`);
  branded empty state (`VLCEmptyLibraryView`, `MediaViewController`).
- `Sources/Settings/Model/SettingsSection.swift` and `Resources/iOS/Settings.bundle/*` — playback history, removed
  video/subtitle rows.
- `Sources/UI Elements/Buttons/AppMenuBarButtonItem.swift`, `Sources/About/*`, `Sources/Onboarding/*`,
  `Resources/en.lproj/Localizable.strings` — branding, About, contact, empty-state copy.
- `Resources/iOS/{Info.plist,Launch Screen.storyboard}`, `Buildsystem/SharedConfig.xcconfig`, app/watch/tvOS asset
  bundles, `Sources/Headers/VLCConstants.h`, `Sources/UI Elements/PresentationTheme.swift` — name, dark default,
  palette, artwork.
- `Sources/Headers/VLC-iOS-Bridging-Header.h` — `DiscourseSecrets.h`, `VLCNetworkImageView.h`.
- Mini-player/queue display files — mini-player notifications, artwork sensor, queue metadata.
- `VLC.xcodeproj/project.pbxproj` — secrets phase, header search paths, file registration.
- New fork-only folders: `Sources/Discourse/{API,Stores,Playback,Downloads,Mixer,UI,DeepLink}`,
  `Buildsystem/{RNNoise,DeepLinks,Testing}`.
