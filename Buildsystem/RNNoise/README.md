# RNNoise playback engine

This directory maintains the native changes for the main player's live **Noise
reduction** switch. The Audio Mixer continues using the unmodified player path.
The app accepts upstream VLCKit while the custom engine is being built: its
noise reduction switch is disabled, and no preference is overwritten.

## Build and activate

Use the Xcode and Python prerequisites documented in `AGENTS.md`. A first native
build downloads and compiles VLC's tools and contrib dependencies; it is much
larger than an app build. Allow network access and several GB of free disk space.

```sh
Buildsystem/RNNoise/build.sh
ruby Buildsystem/RNNoise/activate.rb
```

The build uses isolated checkouts in the gitignored `build/rnnoise/`, applies the
upstream VLCKit patches followed by our patches, and builds release iOS device
and simulator slices. It verifies the upstream binary archive's SHA-256, retains
its other platform slices, and writes the resulting XCFramework to the ignored
`Artifacts/` directory. Activation changes the Xcode dependency to this local
binary package and removes the upstream VLCKit pin. Run the normal app build and
unit tests after activation. Build artifacts must be supplied alongside the
checkout on another machine; they are not checked into Git.
The existing CI build jobs run the native builder before package resolution when
the local dependency is activated. A clean CI build therefore includes the
native toolchain and codec compilation time.

The builder clears inherited compiler/pkg-config flags and uses explicit job
counts to avoid Apple Make's incompatibility with Ninja's pipe jobserver. Its
host zstd tool disables optional LZ4/LZMA formats, preventing Intel Homebrew
libraries from being detected on Apple Silicon; zstd decompression remains enabled.

Pinned sources:

| Component | Revision |
| --- | --- |
| VLCKit 4.0.0-a25 | `8f5ce02f09a7da5d061a24ddac3cb432f2a9b332` |
| libvlc | `005e69e67a8730f128e44bde68437fbb048cf45f` |
| RNNoise 0.1.1 | `6cbfd53eb348a8d394e0757b4025c6ded34eb2b6`, default bundled model |

The official binary URL and checksum are pinned in `build.sh`. Dependency
sources and upstream patches retain their existing licenses; the framing helper
is LGPL-2.1-or-later. Keep RNNoise's BSD attribution and the existing VLC notices.
Distribute these patches and the exact dependency sources with custom binaries.

## Native contract

`prepareNoiseReduction` installs RNNoise once, before playback starts, and fails
when the module is absent. `noiseReductionReady` checks that the filter actually
opened during playback. `applyNoiseReductionEnabled:` returns success/failure
and switches a per-player variable without rebuilding the audio filter chain.
The equalizer API preserves unrelated filter tokens, including RNNoise.

The filter negotiates 48 kHz float input, keeps independent channel state, buffers
complete 480-sample frames, flushes on seeks/discontinuities, and drains its tail.
Processed and original audio share a fixed 960-sample (20 ms) delay. Switching
crossfades over 10 ms. RNNoise remains warm even with the switch off to allow
immediate comparisons; CPU/battery cost therefore remains while bypassed. There
are no allocations in the sample processing loop. Audio-output creation failure
leaves playback available and disables noise reduction.

## Checks

```sh
clang -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined \
  -I Buildsystem/RNNoise/tests Buildsystem/RNNoise/tests/framing.c \
  -o /tmp/rd-rnnoise-framing
/tmp/rd-rnnoise-framing
python3 -m unittest discover -s Buildsystem/RNNoise/tests -p 'test_*.py'
```

For the complete native checks, supply RNNoise 0.1.1 source with `rnnoise.patch`
applied and the patched VLC checkout:
`bash Buildsystem/RNNoise/tests/run.sh <patched-rnnoise-source> <patched-vlc-source>`.
The real-model harness checks whole-buffer/chunked equivalence, finite output,
deterministic reset, original-audio alignment, repeated switching and allocation
failures. Allocation instrumentation also checks 10,000 resets without leaks.
The control harness compiles the actual patched libvlc functions against a small
variable-store double; it checks filter preservation, allocation failure,
capability reporting and 100 toggles without a filter-chain change.
Both C harnesses and the artifact merge test passed locally; listening and device
performance remain separate checks.

`rnnoise.patch` adds an allocation-free reset and checks state allocation
failures. RNNoise 0.1.1's original initializer allocates recurrent buffers and
must not be called repeatedly on an initialized state. The helper also warms up
the model's shared FFT tables during filter creation.

The framing harness substitutes a deterministic one-frame-delay processor to
test buffering, channel isolation, reset, bypass alignment, repeated switching
and allocation failures. It does not establish perceptual RNNoise quality.
`DiscourseNoiseReductionTests` covers service persistence, failure rollback,
notifications, unavailable engines and renderer transitions.
Its native smoke test also passes against the activated framework: 44.1 kHz
stereo playback, 100 live toggles, equalizer coexistence, advancing playback time
and switching while paused/resuming. The device, Intel simulator and Apple
Silicon simulator native builds and the no-watch app build succeeded locally.

The current workspace's Debug Watch identifiers do not match the iOS app, so
simulator tests used these temporary build-only overrides:

```sh
cat > /tmp/rd-rnnoise-test-identifiers.xcconfig <<'EOF'
INFOPLIST_KEY_WKCompanionAppBundleIdentifier = com.oshodiscourse
PRODUCT_BUNDLE_IDENTIFIER[sdk=watchsimulator*] = com.oshodiscourse.watchos
PRODUCT_BUNDLE_IDENTIFIER[sdk=watchos*] = com.oshodiscourse.watchos
EOF
XCODE_XCCONFIG_FILE=/tmp/rd-rnnoise-test-identifiers.xcconfig \
xcodebuild -workspace VLC.xcworkspace -scheme VLC-iOS-Tests -configuration Debug \
  -destination 'platform=iOS Simulator,id=<UDID>' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO test
```

All 119 unit tests passed with the activated engine and these overrides. This
leaves the repository's signing configuration unchanged. Use the standard test
command once the Watch identifiers are aligned.

Before release, test the activated engine on a physical supported iPhone:
streamed/local/downloaded speech, quiet passages, already-cleaned audio, music,
rapid toggling while playing/paused, seeks, queue changes, repeat/shuffle,
equalizer, playback speeds, Bluetooth, interruptions, background and lock-screen
controls, and simultaneous Mixer playback. Require no toggle dropout or queue or
position loss; measure sustained CPU/thermal/battery cost. No physical-device
acceptance results are recorded yet.
