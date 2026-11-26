#!/usr/bin/env bash
# Build ASCII Racer for Windows, Linux, macOS, the web and Android, and
# optionally publish a GitHub release.
#
#   tools/release.sh <version>                 build and package only
#   tools/release.sh <version> --publish       ... then commit the version bump,
#                                              tag v<version>, push, create the
#                                              GitHub release with the builds, and
#                                              publish the web build to GitHub
#                                              Pages (tools/deploy_pages.sh)
#   options: --notes <file>   release notes (default: docs/releases/<version>.md
#                             if it exists, otherwise GitHub's generated notes)
#            --no-smoke       skip the Linux smoke test (needs a display)
#            --only <t>[,<t>] build, package and attach only these targets
#                             (windows, linux, macos, web, android)
#            --prerelease     with --publish: mark the GitHub release a prerelease
#                             (the "latest" release stays; no Pages deploy)
#
# Needs: godot (same version as the installed export templates), zip, tar, and
# for --publish: git and an authenticated gh. Android also needs the Android
# SDK (build-tools with aapt2 and apksigner; Godot's editor setting or
# ANDROID_HOME), Java (keytool), and the release keystore's variables
# GODOT_ANDROID_KEYSTORE_RELEASE_PATH / _USER / _PASSWORD, read from
# ~/.config/ascii-racer/android-release.env (or $ANDROID_RELEASE_ENV) when they
# are not already set.
set -euo pipefail

usage() { sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-1}"; }

ALL_TARGETS="windows linux macos web android"
VERSION="" PUBLISH=0 SMOKE=1 NOTES="" ONLY="" PRERELEASE=0
while [ $# -gt 0 ]; do
	case "$1" in
		--publish) PUBLISH=1 ;;
		--no-smoke) SMOKE=0 ;;
		--notes) NOTES="${2:?--notes needs a file}"; shift ;;
		--only) ONLY="${2:?--only needs a target list}"; shift ;;
		--prerelease) PRERELEASE=1 ;;
		-h|--help) usage 0 ;;
		-*) echo "unknown option: $1" >&2; usage ;;
		*) [ -z "$VERSION" ] || { echo "version given twice" >&2; usage; }; VERSION="$1" ;;
	esac
	shift
done
[ -n "$VERSION" ] || usage
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}([-.][0-9A-Za-z.]+)?$ ]] || { echo "bad version: $VERSION (expected e.g. 0.2 or 1.0.1)" >&2; exit 1; }

TARGETS="$ALL_TARGETS"
if [ -n "$ONLY" ]; then
	TARGETS=""
	for t in ${ONLY//,/ }; do
		case " $ALL_TARGETS " in *" $t "*) ;; *) echo "unknown target: $t (one of: $ALL_TARGETS)" >&2; exit 1 ;; esac
		case " $TARGETS " in *" $t "*) ;; *) TARGETS="${TARGETS:+$TARGETS }$t" ;; esac
	done
fi
want() { case " $TARGETS " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
[ "$PRERELEASE" = 0 ] || [ "$PUBLISH" = 1 ] || echo "note: --prerelease only matters with --publish"

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
echo "targets: $TARGETS"
if want android; then
	# The SDK: Godot's editor setting, else ANDROID_HOME / ANDROID_SDK_ROOT.
	EDITOR_SETTINGS="$(ls "${XDG_CONFIG_HOME:-$HOME/.config}"/godot/editor_settings-4*.tres 2>/dev/null | tail -1 || true)"
	SDK=""
	[ -z "$EDITOR_SETTINGS" ] || SDK="$(sed -n 's|^export/android/android_sdk_path = "\(.*\)"$|\1|p' "$EDITOR_SETTINGS")"
	SDK="${SDK:-${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}}"
	[ -n "$SDK" ] && [ -d "$SDK" ] || { echo "Android SDK not found (Godot's export/android/android_sdk_path or ANDROID_HOME)" >&2; exit 1; }
	BUILD_TOOLS="$(ls -d "$SDK"/build-tools/*/ 2>/dev/null | sort -V | tail -1)"
	AAPT2="${BUILD_TOOLS}aapt2" APKSIGNER="${BUILD_TOOLS}apksigner"
	[ -n "$BUILD_TOOLS" ] && [ -x "$AAPT2" ] && [ -x "$APKSIGNER" ] || { echo "Android build-tools with aapt2 and apksigner missing under $SDK/build-tools" >&2; exit 1; }
	command -v keytool >/dev/null || { echo "keytool not found (Java)" >&2; exit 1; }
	[ -f "$TEMPLATES/android_release.apk" ] || { echo "Android export template missing: $TEMPLATES/android_release.apk" >&2; exit 1; }
	# Release signing: from the environment, else the private env file.
	if [ -z "${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:-}" ] || [ -z "${GODOT_ANDROID_KEYSTORE_RELEASE_USER:-}" ] || [ -z "${GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD:-}" ]; then
		ENV_FILE="${ANDROID_RELEASE_ENV:-$HOME/.config/ascii-racer/android-release.env}"
		# shellcheck disable=SC1090
		[ -f "$ENV_FILE" ] && . "$ENV_FILE"
	fi
	if [ -z "${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:-}" ] || [ -z "${GODOT_ANDROID_KEYSTORE_RELEASE_USER:-}" ] || [ -z "${GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD:-}" ]; then
		echo "Android release signing not set up: GODOT_ANDROID_KEYSTORE_RELEASE_PATH, _USER and _PASSWORD must be set" >&2
		echo "(or exported by ${ANDROID_RELEASE_ENV:-$HOME/.config/ascii-racer/android-release.env})" >&2; exit 1
	fi
	export GODOT_ANDROID_KEYSTORE_RELEASE_PATH GODOT_ANDROID_KEYSTORE_RELEASE_USER GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD
	[ -f "$GODOT_ANDROID_KEYSTORE_RELEASE_PATH" ] || { echo "release keystore not found: $GODOT_ANDROID_KEYSTORE_RELEASE_PATH" >&2; exit 1; }
	# The release certificate's digest (the APK must be signed with it). The
	# password goes through the environment, never the command line.
	RELEASE_CERT="$(keytool -list -v -keystore "$GODOT_ANDROID_KEYSTORE_RELEASE_PATH" -alias "$GODOT_ANDROID_KEYSTORE_RELEASE_USER" \
		-storepass:env GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD 2>/dev/null | sed -n 's/^[[:space:]]*SHA256: //p' | tr -d ':' | tr 'A-F' 'a-f')"
	[ -n "$RELEASE_CERT" ] || { echo "could not read the release keystore (path, alias or password wrong?)" >&2; exit 1; }
	# The Android version code: the commit count (+1 for the version bump commit
	# --publish adds), and above every earlier release's code.
	ANDROID_CODE=$(( $(git rev-list --count HEAD) + 1 ))
	for t in $(git tag -l 'v*'); do
		c="$(git show "$t:export_presets.cfg" 2>/dev/null | sed -n 's|^version/code=\([0-9]*\)$|\1|p' | head -1)"
		[ -z "$c" ] || [ "$c" -lt "$ANDROID_CODE" ] || { echo "Android version code $ANDROID_CODE is not above $t's $c" >&2; exit 1; }
	done
	echo "Android: SDK $SDK, build-tools $(basename "$BUILD_TOOLS"), version code $ANDROID_CODE, release keystore set"
fi
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
if want android; then
	# Only the Android preset has version/name and version/code.
	[ "$(grep -c '^version/name=' export_presets.cfg)" = 1 ] && [ "$(grep -c '^version/code=' export_presets.cfg)" = 1 ] \
		|| { echo "expected one version/name and one version/code (the Android preset) in export_presets.cfg" >&2; exit 1; }
	sed -i -e "s|^version/name=.*|version/name=\"$VERSION\"|" -e "s|^version/code=.*|version/code=$ANDROID_CODE|" export_presets.cfg
	grep -n '^version/' export_presets.cfg
fi
grep -n '^config/version=' project.godot

# ---- build -------------------------------------------------------------------
rm -rf "$OUT"
for t in $TARGETS; do rm -rf "build/$t"; mkdir -p "build/$t"; done
mkdir -p "$OUT"
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
want windows && export_target "Windows Desktop" build/windows/ascii-racer.exe
want linux && export_target "Linux" build/linux/ascii-racer.x86_64
want macos && export_target "macOS" build/macos/ascii-racer-macos.zip
if want web; then
	export_target "Web" build/web/index.html
	# The web build is several files; all of them must be there, or nothing ships.
	for f in index.html index.js index.wasm index.pck; do
		[ -s "build/web/$f" ] || { echo "web export incomplete: build/web/$f missing or empty" >&2; exit 1; }
	done
fi
want linux && chmod +x build/linux/ascii-racer.x86_64
if want android; then
	export_target "Android" build/android/ascii-racer.apk
	step "Verify the APK"
	APK=build/android/ascii-racer.apk
	"$APKSIGNER" verify "$APK" || { echo "apksigner: the APK does not verify" >&2; exit 1; }
	APK_CERT="$("$APKSIGNER" verify --print-certs "$APK" 2>/dev/null | sed -n 's/^Signer #1 certificate SHA-256 digest: //p' | tr 'A-F' 'a-f')"
	[ "$APK_CERT" = "$RELEASE_CERT" ] || { echo "the APK is not signed with the release keystore (got $APK_CERT)" >&2; exit 1; }
	BADGING="$("$AAPT2" dump badging "$APK")"
	echo "$BADGING" | grep -q "^package: name='com.eiwe.asciiracer' versionCode='$ANDROID_CODE' versionName='$VERSION'" \
		|| { echo "$BADGING" | head -1 >&2; echo "unexpected package, version code or name" >&2; exit 1; }
	echo "$BADGING" | grep -qx "native-code: 'arm64-v8a'" || { echo "$BADGING" | grep native-code >&2; echo "expected native-code arm64-v8a only" >&2; exit 1; }
	CONTENTS="$(unzip -l "$APK")"
	for f in assets/project.binary assets/assets/audio/sounds.cfg assets/game/game.tscn.remap; do
		echo "$CONTENTS" | grep -q " $f\$" || { echo "APK is missing the game data: $f" >&2; exit 1; }
	done
	echo "ok: signed with the release key, com.eiwe.asciiracer $VERSION ($ANDROID_CODE), arm64-v8a, game data present"
fi

# The imported textures must not have been changed by the headless run (it once
# flipped the kit's colormap to VRAM-compressed, which changes the look).
if [ -d .git ] && ! git diff --quiet -- '*.import'; then
	echo "export changed .import files; refusing to continue:" >&2; git diff --stat -- '*.import' >&2; exit 1
fi

# ---- smoke test --------------------------------------------------------------
if [ "$SMOKE" = 1 ] && want linux; then
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
AND="$OUT/ascii-racer-$VERSION-android-arm64.apk"
PACKAGES=()
if want windows; then (cd build/windows && zip -q -9 "$ROOT/$WIN" ascii-racer.exe); PACKAGES+=("$WIN"); fi
if want linux; then tar -C build/linux -czf "$LIN" ascii-racer.x86_64; PACKAGES+=("$LIN"); fi
if want macos; then cp build/macos/ascii-racer-macos.zip "$MAC"; PACKAGES+=("$MAC"); fi
if want web; then (cd build/web && zip -q -9 -r "$ROOT/$WEB" .); PACKAGES+=("$WEB"); fi
if want android; then cp build/android/ascii-racer.apk "$AND"; PACKAGES+=("$AND"); fi
for f in "${PACKAGES[@]}"; do [ -s "$f" ] || { echo "package missing: $f" >&2; exit 1; }; done
(cd "$OUT" && for f in "${PACKAGES[@]}"; do basename "$f"; done | xargs sha256sum > SHA256SUMS.txt)
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
[ "$PRERELEASE" = 0 ] || NOTE_ARGS+=(--prerelease)
gh release create "$TAG" "${PACKAGES[@]}" "$OUT/SHA256SUMS.txt" --title "ASCII Racer $VERSION" --verify-tag "${NOTE_ARGS[@]}"
gh release view "$TAG" --json url --jq .url
if want web && [ "$PRERELEASE" = 0 ]; then
	step "Web build to GitHub Pages"
	# The root of the site; preview subdirectories (deploy_pages.sh --subdir) stay.
	tools/deploy_pages.sh origin
else
	echo "GitHub Pages left as it is (no web build, or a prerelease)"
fi
