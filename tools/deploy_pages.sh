#!/usr/bin/env bash
# Publish the web build (build/web/) to GitHub Pages. The gh-pages branch is
# always replaced by one fresh commit with no history (so the large WebAssembly
# file never piles up), holding the site as it should now be:
#
#   tools/deploy_pages.sh [remote]                       the root build: replaces the files at the
#                                                        top of the site, keeps preview subdirectories
#   tools/deploy_pages.sh [remote] --subdir <name>       a preview: build/web/ into <name>/ (replaced
#                                                        whole), everything else kept as it is
#   tools/deploy_pages.sh [remote] --remove-subdir <name>  takes preview <name>/ away, keeps the rest
#
# remote: default origin (a remote name, URL or path). The current gh-pages tree
# is fetched shallowly (depth 1) to carry over what is kept; a remote without a
# gh-pages branch starts from an empty site. Previews are the site's top-level
# directories (the root build itself has none). .nojekyll stays at the top.
#
# Everything happens in a temporary directory: the working tree, the index and
# the current branch are not touched. The commit uses this repository's git
# identity (user.name / user.email). Refuses if build/web/ is incomplete.
# WEB_DIR=<dir> publishes another folder (for testing).
set -euo pipefail

usage() { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
REMOTE=origin
SUBDIR=""
REMOVE=""
while [ $# -gt 0 ]; do
	case "$1" in
		--subdir) SUBDIR="${2:-}"; shift 2 ;;
		--remove-subdir) REMOVE="${2:-}"; shift 2 ;;
		-h|--help) usage 0 ;;
		-*) echo "unknown option $1" >&2; usage 1 ;;
		*) REMOTE="$1"; shift ;;
	esac
done
[ -z "$SUBDIR" ] || [ -z "$REMOVE" ] || { echo "--subdir and --remove-subdir together make no sense" >&2; exit 1; }
for n in "$SUBDIR" "$REMOVE"; do
	if [ -n "$n" ] && ! [[ "$n" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
		echo "bad subdirectory name: $n (letters, digits, . _ -; no slashes)" >&2; exit 1
	fi
done
WEB="${WEB_DIR:-$ROOT/build/web}"
if [ -z "$REMOVE" ]; then
	for f in index.html index.js index.wasm index.pck; do
		[ -s "$WEB/$f" ] || { echo "web build incomplete: $WEB/$f missing or empty (export the \"Web\" preset first)" >&2; exit 1; }
	done
fi
if URL="$(git remote get-url "$REMOTE" 2>/dev/null)"; then :; else URL="$REMOTE"; fi
NAME="$(git config user.name || true)"
EMAIL="$(git config user.email || true)"
[ -n "$NAME" ] && [ -n "$EMAIL" ] || { echo "git user.name / user.email are not set" >&2; exit 1; }
SOURCE="$(git describe --tags --always --dirty 2>/dev/null || echo unknown)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FETCH="$TMP/fetch"
SITE="$TMP/site"
mkdir -p "$SITE"
git -C "$TMP" init -q fetch
# The site as it is now (nothing, if there is no gh-pages yet).
if git ls-remote --exit-code --heads "$URL" gh-pages >/dev/null 2>&1; then
	git -C "$FETCH" fetch -q --depth 1 "$URL" gh-pages
	git -C "$FETCH" archive FETCH_HEAD | tar -x -C "$SITE"
	HAD=yes
else
	HAD=no
fi

if [ -n "$REMOVE" ]; then
	[ -d "$SITE/$REMOVE" ] || { echo "no preview $REMOVE/ on gh-pages" >&2; exit 1; }
	rm -rf "${SITE:?}/$REMOVE"
	WHAT="removed $REMOVE/"
elif [ -n "$SUBDIR" ]; then
	rm -rf "${SITE:?}/$SUBDIR"
	mkdir -p "$SITE/$SUBDIR"
	cp -a "$WEB/." "$SITE/$SUBDIR/"
	WHAT="preview $SUBDIR/ from $SOURCE"
else
	# Root: the top-level files are the old build; directories are previews.
	find "$SITE" -mindepth 1 -maxdepth 1 -type f -delete
	cp -a "$WEB/." "$SITE/"
	WHAT="root from $SOURCE"
fi
touch "$SITE/.nojekyll"

KEPT="$(find "$SITE" -mindepth 1 -maxdepth 1 -type d -printf '%f ' | sed 's/ $//')"
git -C "$SITE" init -q
git -C "$SITE" checkout -q --orphan gh-pages
git -C "$SITE" add -A
git -C "$SITE" -c user.name="$NAME" -c user.email="$EMAIL" -c commit.gpgsign=false \
	commit -q -m "Web build of ASCII Racer: $WHAT"
git -C "$SITE" push -q --force "$URL" gh-pages:gh-pages
echo "published $(git -C "$SITE" rev-parse --short HEAD) to gh-pages on $URL: $WHAT (previous gh-pages: $HAD; previews now: ${KEPT:-none})"
