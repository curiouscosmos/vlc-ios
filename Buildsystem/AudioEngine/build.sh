#!/bin/bash
# Copyright (c) 2026 Sandalbar Enterprises, Inc. See COPYING.
set -euo pipefail
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
unset CFLAGS CXXFLAGS CPPFLAGS LDFLAGS CPATH LIBRARY_PATH PKG_CONFIG_PATH
# Explicit counts bypass Ninja's pipe jobserver, incompatible with Apple's Make.
export MAKEFLAGS=-j4 MESONCOMPILEFLAGS=-j4 CMAKE_BUILD_PARALLEL_LEVEL=4
script_dir=$(cd "$(dirname "$0")" && pwd)
repo_dir=$(cd "$script_dir/../.." && pwd)
work_dir="$repo_dir/build/audio-engine"
mkdir -p "$work_dir"

# Each source checkout is isolated from Xcode's generated package checkouts.
if [[ ! -d "$work_dir/VLCKit" ]]; then
    git clone https://code.videolan.org/videolan/VLCKit.git "$work_dir/VLCKit"
    git -C "$work_dir/VLCKit" checkout 8f5ce02f09a7da5d061a24ddac3cb432f2a9b332
fi
if [[ ! -d "$work_dir/vlc" ]]; then
    git clone https://github.com/videolan/vlc.git "$work_dir/vlc"
    git -C "$work_dir/vlc" checkout 005e69e67a8730f128e44bde68437fbb048cf45f
fi
[[ $(git -C "$work_dir/VLCKit" rev-parse HEAD) == 8f5ce02f09a7da5d061a24ddac3cb432f2a9b332 ]]
[[ $(git -C "$work_dir/vlc" rev-parse HEAD) == 005e69e67a8730f128e44bde68437fbb048cf45f ]]
patch_fingerprint=$(shasum -a 256 "$script_dir/audio-output.patch" "$script_dir/ios-audio.patch")
if [[ -f "$work_dir/.patched" ]]; then
    if [[ $(cat "$work_dir/.patched") != "$patch_fingerprint" ]]; then
        echo 'Native patches changed. Move build/audio-engine aside and run this script again.' >&2
        exit 1
    fi
else
    git -C "$work_dir/vlc" apply "$work_dir/VLCKit"/libvlc/patches/*.patch
    git -C "$work_dir/vlc" apply "$script_dir/audio-output.patch" "$script_dir/ios-audio.patch"
    printf '%s\n' "$patch_fingerprint" > "$work_dir/.patched"
fi
# VLCKit's Xcode project resolves headers and static archives through this path.
if [[ ! -e "$work_dir/VLCKit/libvlc/vlc" ]]; then
    ln -s "$work_dir/vlc" "$work_dir/VLCKit/libvlc/vlc"
fi
[[ $(cd "$work_dir/VLCKit/libvlc/vlc" && pwd -P) == $(cd "$work_dir/vlc" && pwd -P) ]]
cd "$work_dir/VLCKit"
# Only the iOS wrapper is built here. Keep its dependency list in sync with the linked codecs.
ruby -rxcodeproj -e '
    project = Xcodeproj::Project.open("VLCKit.xcodeproj")
    project.targets.each do |target|
        target.frameworks_build_phase.files.select do |file|
            file.file_ref&.display_name == "VideoToolbox.framework"
        end.each(&:remove_from_project)
    end
    project.save
'
printf 'CODE_SIGNING_ALLOWED = NO\nCODE_SIGNING_REQUIRED = NO\n' > "$work_dir/Unsigned.xcconfig"
export XCODE_XCCONFIG_FILE="$work_dir/Unsigned.xcconfig"
./compileAndBuildVLCKit.sh -f -a all -r -e "$work_dir/vlc"

# Retain the upstream watch/tv/vision/mac slices used by the existing schemes.
archive="$work_dir/upstream.zip"
if [[ ! -f "$archive" ]]; then
    curl --fail --location --output "$archive.partial" https://download.videolan.org/cocoapods/unstable/VLCKit-4.0-20260929-1631.zip
    mv "$archive.partial" "$archive"
fi
echo "f37c8dbdd4427d1a3f5d75dc4b8bd1ae863cef4426f9a405a2fd1c5c9012f1fb  $archive" | shasum -a 256 -c -
for slice in "$work_dir/VLCKit/build/iOS/VLCKit.xcframework"/ios-*/VLCKit.framework/VLCKit; do
    "$script_dir/check-slice.sh" "$slice"
done
python3 "$script_dir/package.py" "$work_dir" "$script_dir/Artifacts"
echo 'Audio-only iOS artifact built.'
