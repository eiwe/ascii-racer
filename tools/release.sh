#!/usr/bin/env bash
# Build ASCII Racer for Windows, Linux, macOS and the web, and optionally
# publish a GitHub release.
#
#   tools/release.sh <version>                 build and package only
#   tools/release.sh <version> --publish       ... then commit the version bump,
#                                              tag v<version>, push, and create
#                                              the GitHub release with the builds
#   options: --notes <file>   release notes (default: docs/releases/<version>.md
#                             if it exists, otherwise GitHub's generated notes)
#            --no-smoke       skip the Linux smoke test (needs a display)
#
# Needs: godot (same version as the installed export templates), zip, tar, and
# for --publish: git and an authenticated gh.
set -euo pipefail

usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-1}"; }

VERSION="" PUBLISH=0 SMOKE=1 NOTES=""
while [ $# -gt 0 ]; do
	case "$1" in
		--publish) PUBLISH=1 ;;
		--no-smoke) SMOKE=0 ;;
		--notes) NOTES="${2:?--notes needs a file}"; shift ;;
		-h|--help) usage 0 ;;
		-*) echo "unknown option: $1" >&2; usage ;;
		*) [ -z "$VERSION" ] || { echo "version given twice" >&2; usage; }; VERSION="$1" ;;
	esac
	shift
done
[ -n "$VERSION" ] || usage
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}([-.][0-9A-Za-z.]+)?$ ]] || { echo "bad version: $VERSION (expected e.g. 0.2 or 1.0.1)" >&2; exit 1; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
TAG="v$VERSION"
OUT="build/release/$VERSION"
step() { printf '\n== %s\n' "$*"; }

# ---- preflight ---------------------------------------------------------------
step "Preflight"
command -v godot >/dev/null || { echo "godot not found" >&2; exit 1; }
GODOT_VERSION="$(godot --version | head -1)"            # e.g. 4.7.2.stable.arch_linux.ed1daf0bf
# Templates live in a folder named <number>.<status>, e.g. 4.7.2.stable
TEMPLATE_VERSION="$(echo "$GODOT_VERSION" | sed -E 's/^([0-9]+(\.[0-9]+)*\.[a-z]+[0-9]*)\..*$/\1/')"
TEMPLATES="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/$TEMPLATE_VERSION"
[ -d "$TEMPLATES" ] || { echo "export templates missing: $TEMPLATES" >&2; exit 1; }
echo "godot $GODOT_VERSION, templates $TEMPLATES"
if [ "$PUBLISH" = 1 ]; then
	command -v gh >/dev/null || { echo "gh not found" >&2; exit 1; }
	gh auth status >/dev/null 2>&1 || { echo "gh is not logged in" >&2; exit 1; }
	[ -z "$(git status --porcelain)" ] || { echo "working tree is not clean; commit or stash first" >&2; git status --short >&2; exit 1; }
	if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then echo "tag $TAG already exists" >&2; exit 1; fi
	if gh release view "$TAG" >/dev/null 2>&1; then echo "release $TAG already exists on GitHub" >&2; exit 1; fi
fi
if [ -z "$NOTES" ] && [ -f "docs/releases/$VERSION.md" ]; then NOTES="docs/releases/$VERSION.md"; fi
[ -z "$NOTES" ] || [ -f "$NOTES" ] || { echo "notes file not found: $NOTES" >&2; exit 1; }

# ---- version -----------------------------------------------------------------
step "Version $VERSION"
if grep -q '^config/version=' project.godot; then
	sed -i "s|^config/version=.*|config/version=\"$VERSION\"|" project.godot
else
	sed -i "s|^config/name=\(.*\)$|config/name=\1\nconfig/version=\"$VERSION\"|" project.godot
fi
sed -i -e "s|^application/short_version=.*|application/short_version=\"$VERSION\"|" \
	-e "s|^application/version=.*|application/version=\"$VERSION\"|" export_presets.cfg
grep -n '^config/version=' project.godot

# ---- build -------------------------------------------------------------------
rm -rf build/windows build/linux build/macos build/web "$OUT"
mkdir -p build/windows build/linux build/macos build/web "$OUT"
touch build/.gdignore

export_target() { # <preset> <output>
	step "Export: $1"
	local log; log="$(mktemp)"
	if ! godot --headless --path . --export-release "$1" "$2" >"$log" 2>&1; then
		tail -30 "$log" >&2; rm -f "$log"; echo "export failed: $1" >&2; exit 1
	fi
	if grep -E '^(ERROR|SCRIPT ERROR)' "$log" >&2; then rm -f "$log"; echo "export reported errors: $1" >&2; exit 1; fi
	rm -f "$log"
	[ -s "$2" ] || { echo "export produced nothing: $2" >&2; exit 1; }
	ls -la "$2" | awk '{print $5, $9}'
}
export_target "Windows Desktop" build/windows/ascii-racer.exe
export_target "Linux" build/linux/ascii-racer.x86_64
export_target "macOS" build/macos/ascii-racer-macos.zip
export_target "Web" build/web/index.html
# The web build is several files; all of them must be there, or nothing ships.
for f in index.html index.js index.wasm index.pck; do
	[ -s "build/web/$f" ] || { echo "web export incomplete: build/web/$f missing or empty" >&2; exit 1; }
done
chmod +x build/linux/ascii-racer.x86_64

# The imported textures must not have been changed by the headless run (it once
# flipped the kit's colormap to VRAM-compressed, which changes the look).
if [ -d .git ] && ! git diff --quiet -- '*.import'; then
	echo "export changed .import files; refusing to continue:" >&2; git diff --stat -- '*.import' >&2; exit 1
fi

# ---- smoke test --------------------------------------------------------------
if [ "$SMOKE" = 1 ]; then
	step "Smoke test (Linux build, opens a window briefly)"
	SMOKE_DIR="$(mktemp -d)"
	if ! timeout 90 build/linux/ascii-racer.x86_64 --audio-driver Dummy --fixed-fps 120 -- --drivetest="$SMOKE_DIR" --dtonly=spawn >"$SMOKE_DIR/log.txt" 2>&1; then
		tail -20 "$SMOKE_DIR/log.txt" >&2; echo "smoke test failed" >&2; exit 1
	fi
	grep -q 'wheels grounded 4' "$SMOKE_DIR/results.txt" || { cat "$SMOKE_DIR/results.txt" >&2; echo "smoke test: car did not settle on its wheels" >&2; exit 1; }
	if grep -E '^(ERROR|SCRIPT ERROR)' "$SMOKE_DIR/log.txt" >&2; then echo "smoke test printed errors" >&2; exit 1; fi
	echo "ok: $(grep 'wheels grounded' "$SMOKE_DIR/results.txt" | sed 's/^ *//')"
	rm -rf "$SMOKE_DIR"
fi

# ---- package -----------------------------------------------------------------
step "Package"
WIN="$OUT/ascii-racer-$VERSION-windows-x86_64.zip"
LIN="$OUT/ascii-racer-$VERSION-linux-x86_64.tar.gz"
MAC="$OUT/ascii-racer-$VERSION-macos-universal.zip"
WEB="$OUT/ascii-racer-$VERSION-web.zip"
(cd build/windows && zip -q -9 "$ROOT/$WIN" ascii-racer.exe)
tar -C build/linux -czf "$LIN" ascii-racer.x86_64
cp build/macos/ascii-racer-macos.zip "$MAC"
(cd build/web && zip -q -9 -r "$ROOT/$WEB" .)
for f in "$WIN" "$LIN" "$MAC" "$WEB"; do [ -s "$f" ] || { echo "package missing: $f" >&2; exit 1; }; done
(cd "$OUT" && sha256sum ./*.zip ./*.tar.gz | sed 's| \./| |' > SHA256SUMS.txt)
ls -la "$OUT" | awk 'NR>1 && $9 !~ /^\.+$/ {printf "%10d  %s\n", $5, $9}'

if [ "$PUBLISH" = 0 ]; then
	printf '\nBuilt and packaged in %s (not published; pass --publish to release).\n' "$OUT"
	exit 0
fi

# ---- publish -----------------------------------------------------------------
step "Publish $TAG"
if [ -n "$(git status --porcelain -- project.godot export_presets.cfg)" ]; then
	git add project.godot export_presets.cfg
	git commit -q -m "Release $VERSION"
	echo "committed version bump"
fi
[ -z "$(git status --porcelain)" ] || { echo "unexpected changes after the build:" >&2; git status --short >&2; exit 1; }
git tag -a "$TAG" -m "ASCII Racer $VERSION"
git push -q origin HEAD
git push -q origin "$TAG"
if [ -n "$NOTES" ]; then NOTE_ARGS=(--notes-file "$NOTES"); else NOTE_ARGS=(--generate-notes); fi
gh release create "$TAG" "$WIN" "$LIN" "$MAC" "$WEB" "$OUT/SHA256SUMS.txt" --title "ASCII Racer $VERSION" --verify-tag "${NOTE_ARGS[@]}"
gh release view "$TAG" --json url --jq .url
