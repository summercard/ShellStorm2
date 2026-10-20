#!/bin/bash
# Render a standalone .svg to PNG with headless Chrome.
# usage: render_svg.sh <in.svg> <out.png> [width] [height] [scale]
#   width/height = CSS px of the SVG canvas (default 1680x1080)
#   scale        = device scale factor (default 2 -> output is 2x)
set -euo pipefail

IN="${1:?usage: render_svg.sh <in.svg> <out.png> [w] [h] [scale]}"
OUT="${2:?usage: render_svg.sh <in.svg> <out.png> [w] [h] [scale]}"
W="${3:-1680}"
H="${4:-1080}"
S="${5:-2}"

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
[ -x "$CHROME" ] || { echo "Chrome not found at $CHROME" >&2; exit 1; }

# absolute paths: Chrome resolves relative --screenshot targets against its cwd
case "$IN"  in /*) ;; *) IN="$(cd "$(dirname "$IN")" && pwd)/$(basename "$IN")" ;; esac
case "$OUT" in /*) ;; *) OUT="$(pwd)/$OUT" ;; esac

"$CHROME" --headless --disable-gpu --hide-scrollbars \
  --force-device-scale-factor="$S" --window-size="$W,$H" \
  --screenshot="$OUT" "$IN" 2>&1 | grep -E "bytes written|ERROR:.*(screenshot|cannot)" || true

[ -s "$OUT" ] || { echo "render failed: $OUT is missing or empty" >&2; exit 1; }
python3 - "$OUT" <<'PY'
import struct, sys
p = sys.argv[1]
d = open(p, 'rb').read(33)
if d[:8] == b'\x89PNG\r\n\x1a\n':
    w, h = struct.unpack('>II', d[16:24])
    print(f"{p}: {w}x{h}, {len(open(p,'rb').read())} bytes")
else:
    print(f"{p}: not a PNG", file=sys.stderr); sys.exit(1)
PY
