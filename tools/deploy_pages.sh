#!/usr/bin/env bash
# Publish the web build (build/web/) to GitHub Pages: the gh-pages branch is
# replaced by one fresh commit holding the build plus .nojekyll, so the large
# WebAssembly file never piles up in history.
#
#   tools/deploy_pages.sh [remote]     default: origin (a remote name, URL or path)
#
# The commit is built in a temporary repository: the working tree, the index
# and the current branch are not touched. It is made with this repository's
# git identity (user.name / user.email). Refuses if build/web/ is incomplete.
# WEB_DIR=<dir> publishes another folder (for testing).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
REMOTE="${1:-origin}"
WEB="${WEB_DIR:-$ROOT/build/web}"

for f in index.html index.js index.wasm index.pck; do
	[ -s "$WEB/$f" ] || { echo "web build incomplete: $WEB/$f missing or empty (export the \"Web\" preset first)" >&2; exit 1; }
done
if URL="$(git remote get-url "$REMOTE" 2>/dev/null)"; then :; else URL="$REMOTE"; fi
NAME="$(git config user.name || true)"
EMAIL="$(git config user.email || true)"
[ -n "$NAME" ] && [ -n "$EMAIL" ] || { echo "git user.name / user.email are not set" >&2; exit 1; }
SOURCE="$(git describe --tags --always --dirty 2>/dev/null || echo unknown)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git -C "$TMP" init -q
git -C "$TMP" checkout -q --orphan gh-pages
cp -a "$WEB/." "$TMP/"
touch "$TMP/.nojekyll"
git -C "$TMP" add -A
git -C "$TMP" -c user.name="$NAME" -c user.email="$EMAIL" -c commit.gpgsign=false \
	commit -q -m "Web build of ASCII Racer $SOURCE"
git -C "$TMP" push -q --force "$URL" gh-pages:gh-pages
echo "published $(git -C "$TMP" rev-parse --short HEAD) ($SOURCE) to gh-pages on $URL"
