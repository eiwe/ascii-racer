#!/usr/bin/env bash
# Serve the web build (build/web/, made by tools/release.sh or an export of the
# "Web" preset) on this machine only, to try it in a browser.
#
#   tools/serve_web.sh [port] [seconds]     default port 8060, runs until Ctrl-C
#                                           (or for <seconds> if given)
#
# Then open http://127.0.0.1:<port>/ . The build is the non-threaded variant,
# which needs no special headers; the cross-origin isolation headers are sent
# anyway, so a threaded export would work from here too.
set -euo pipefail

PORT="${1:-8060}"
SECONDS_LIMIT="${2:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$ROOT/build/web"
[ -f "$DIR/index.html" ] || { echo "no web build in $DIR (export the \"Web\" preset first)" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 not found" >&2; exit 1; }

echo "serving $DIR at http://127.0.0.1:$PORT/  (Ctrl-C to stop)"
RUN=(python3 -c '
import functools, http.server, sys
class H(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map, ".wasm": "application/wasm", ".pck": "application/octet-stream"}
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()
http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), functools.partial(H, directory=sys.argv[2])).serve_forever()
' "$PORT" "$DIR")
if [ -n "$SECONDS_LIMIT" ]; then
	timeout "$SECONDS_LIMIT" "${RUN[@]}" || [ $? -eq 124 ]
else
	exec "${RUN[@]}"
fi
