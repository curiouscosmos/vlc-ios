#!/bin/bash
# Copyright (c) 2026 Sandalbar Enterprises, Inc. See COPYING.
set -euo pipefail

binary=${1:?Usage: check-slice.sh path/to/VLCKit}
linked=$(xcrun otool -L "$binary")
if [[ $linked == *VideoToolbox.framework/VideoToolbox* ]]; then
    echo "Unexpected VideoToolbox dependency in $binary" >&2
    exit 1
fi
symbols=$(mktemp)
trap 'rm -f "$symbols"' EXIT

for arch in $(xcrun lipo -archs "$binary"); do
    xcrun nm -arch "$arch" -j "$binary" > "$symbols"
    if grep -Ei 'rnnoise|_VT(Decompression|Compression)Session|_Init(VideoDec|VideoHwDec|SubtitleDec)|_vlc_entry__(video_output|video_filter|video_chroma|video_splitter|spu|text_renderer|visualization)_|_vlc_entry__codec_.*(videotoolbox|rawvideo|dav1d|libvpx|theora|libass)|_ff_(h26[1345]|hevc|vvc|av1|vp[689]|mpeg[124]video|mjpeg|theora)_(decoder|encoder)' "$symbols"; then
        echo "Retired codec or playback module in $arch of $binary" >&2
        exit 1
    fi
    for module in demux_avformat_libavformat codec_avcodec_libavcodec codec_libmpg123 misc_libsecuretransport audio_filter_equalizer audio_filter_resampler_libsoxr audio_output_apple_audiounit_ios stream_out_chromecast_libstream_out_chromecast codec_jpeg codec_png; do
        if ! grep -qx "_vlc_entry__${module}" "$symbols"; then
            echo "Missing $module in $arch of $binary" >&2
            exit 1
        fi
    done
done
