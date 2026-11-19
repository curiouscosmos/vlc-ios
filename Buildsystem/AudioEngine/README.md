# iOS audio engine

Run `Buildsystem/AudioEngine/build.sh` from a clean checkout before resolving Xcode packages. The script checks out the pinned VLC and VLCKit revisions under ignored `build/audio-engine/`, applies the VLCKit patches and the two fork patches, and builds the iPhone device and both simulator architectures. The root project references this local package directly. A missing XCFramework fails package resolution.

`ios-audio.patch` limits FFmpeg to audio codecs and keeps container demuxing, including containers with both audio and video. It excludes video codec and display plug-ins from the iOS static module table and blocks video and subtitle stream selection even for forced requests or Chromecast. A video-only item reports a playback error before the native queue can advance. Still-image loaders and embedded album artwork remain available. The preparser keeps its thumbnail API for compatibility and rejects video thumbnail requests. AVFoundation combines the selected audio and a photo or video for MP4 export.

`audio-output.patch` preserves handling of empty resampler output blocks and the existing native build-tool fixes. `package.py` replaces only the pinned upstream XCFramework’s iOS slices. The other platforms retain the original slices and license. If the patch fingerprint changes, move the ignored work directory aside and rebuild. Never patch Xcode's dependency checkouts.

## Verification

- Run `python3 Buildsystem/AudioEngine/tests/test_package.py` and `ruby Buildsystem/scripts/check_ios_feature_surface.rb`.
- Build both app schemes from clean outputs and run `VLC-iOS-Tests` and the playback/clip UI suites. Follow the streaming seek instructions in AGENTS.md.
- Review `build/audio-engine/vlc/build-*/static-lib/static-module-list.c` and each `contrib/contrib-*/ffmpeg/vlc_build/config_components.h`. Check for audio decoder, container, TLS, Chromecast, equalizer and resampler support, and the absence of video decoders, encoders and rendering modules. The build checks symbols in each iOS architecture before packaging.
- Run `Buildsystem/AudioEngine/check-slice.sh <archive>/Products/Applications/<app>.app/Frameworks/VLCKit.framework/VLCKit` on the Release archive. If local module symbols were stripped by Xcode, pass the matching VLCKit DWARF binary from the archive dSYM and inspect linked frameworks with `xcrun otool -L`. Inspect the app and media-library framework symbols too. Codec-independent container and compatibility symbols are expected.
- Before resubmission, verify casting, audio routes, interruptions, background and lock-screen playback, and export synchronization on physical devices. Check mixed-container audio, video-only rejection, artwork, equalizer, mixer, and Files export of both audio and video.
