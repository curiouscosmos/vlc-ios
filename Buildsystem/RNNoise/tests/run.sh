#!/bin/bash
# Copyright (c) 2026 Sandalbar Enterprises, Inc. See COPYING.
# Usage: bash Buildsystem/RNNoise/tests/run.sh <patched RNNoise source> <patched VLC source>
set -euo pipefail
test_dir=$(cd "$(dirname "$0")" && pwd)
rnnoise_dir=$(cd "${1:?Supply the patched RNNoise 0.1.1 source directory}" && pwd)
vlc_dir=$(cd "${2:?Supply the patched VLC source directory}" && pwd)
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT
flags=(-std=c11 -O1 -g -fsanitize=address,undefined)
clang "${flags[@]}" -Wall -Wextra -Werror -I "$test_dir" "$test_dir/framing.c" -o "$temp_dir/framing"
"$temp_dir/framing"
includes=(-I "$rnnoise_dir/include" -I "$rnnoise_dir/src")
clang "${flags[@]}" "${includes[@]}" -Dmalloc=rd_test_malloc -Dcalloc=rd_test_calloc \
  -Dfree=rd_test_free -c "$rnnoise_dir/src/denoise.c" -o "$temp_dir/denoise.o"
sources=()
for source in rnn rnn_data rnn_reader pitch kiss_fft celt_lpc; do
    sources+=("$rnnoise_dir/src/$source.c")
done
clang "${flags[@]}" "${includes[@]}" -DRD_ALLOCATION_TEST "$test_dir/real_model.c" \
  "$temp_dir/denoise.o" "${sources[@]}" -o "$temp_dir/real_model"
"$temp_dir/real_model"
python3 - "$vlc_dir/lib/media_player.c" "$temp_dir/control_under_test.h" <<'PY'
import sys
from pathlib import Path
source = Path(sys.argv[1]).read_text()
start = source.index('/* Call with the player lock held:')
end = source.index('static libvlc_player_program_t *', start)
Path(sys.argv[2]).write_text(source[start:end])
PY
clang "${flags[@]}" -Wall -Wextra -Werror -I "$temp_dir" "$test_dir/control.c" -o "$temp_dir/control"
"$temp_dir/control"
python3 -m unittest discover -s "$test_dir" -p 'test_*.py'
