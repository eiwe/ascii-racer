#!/usr/bin/env bash
# Re-record the README's hero animation and logo image from the game's opening
# demo reel.
#
#   tools/make_hero.sh [seconds]      default 12
#
# Writes: docs/images/hero.gif   animated hero for the README
#         docs/images/logo.png   still of the finished logo
#         build/hero/ascii-racer-reel.mp4   full-resolution clip (not committed;
#                                           attach it to a release if wanted)
#
# Needs a display (Godot's movie recorder opens a window), godot and ffmpeg.
set -euo pipefail

SECONDS_LONG="${1:-12}"
FPS=30                 # recording rate
GIF_FPS=15
GIF_WIDTH=800
LOGO_AT=4.5            # seconds: after the glint, while the logo is held

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
command -v godot >/dev/null || { echo "godot not found" >&2; exit 1; }
command -v ffmpeg >/dev/null || { echo "ffmpeg not found" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FRAMES=$(awk -v s="$SECONDS_LONG" -v f="$FPS" 'BEGIN { printf "%d", s * f }')

echo "== Recording $SECONDS_LONG s ($FRAMES frames)"
# Silent: the hero has no sound, and the recording must not play through the speakers.
# Quit through the game's own path (it stops all sound first); Godot's
# --quit-after ends it mid-playback and prints leak errors.
godot --audio-driver Dummy --path . --fixed-fps "$FPS" --write-movie "$WORK/f.png" -- --quitafter="$SECONDS_LONG" >"$WORK/log.txt" 2>&1 \
	|| { tail -20 "$WORK/log.txt" >&2; echo "recording failed" >&2; exit 1; }
if grep -E '^(ERROR|SCRIPT ERROR)' "$WORK/log.txt" >&2; then echo "recording printed errors" >&2; exit 1; fi
COUNT=$(find "$WORK" -name 'f*.png' | wc -l)
[ "$COUNT" -ge "$FRAMES" ] || { echo "expected $FRAMES frames, got $COUNT" >&2; exit 1; }
# The game's quit lets a few more frames run while the sound stops: drop them.
find "$WORK" -name 'f*.png' | sort | tail -n +"$((FRAMES + 1))" | xargs -r rm -f

mkdir -p docs/images build/hero
touch build/.gdignore

echo "== Logo still"
LOGO_FRAME=$(awk -v s="$LOGO_AT" -v f="$FPS" 'BEGIN { printf "%08d", s * f }')
ffmpeg -v error -y -i "$WORK/f$LOGO_FRAME.png" -frames:v 1 -update 1 docs/images/logo.png

echo "== GIF"
FILTER="fps=$GIF_FPS,scale=$GIF_WIDTH:-1:flags=lanczos"
ffmpeg -v error -y -framerate "$FPS" -i "$WORK/f%08d.png" -vf "$FILTER,palettegen=max_colors=96:stats_mode=diff" -update 1 "$WORK/palette.png"
ffmpeg -v error -y -framerate "$FPS" -i "$WORK/f%08d.png" -i "$WORK/palette.png" \
	-lavfi "$FILTER [x]; [x][1:v] paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" docs/images/hero.gif

echo "== MP4"
ffmpeg -v error -y -framerate "$FPS" -i "$WORK/f%08d.png" -c:v libx264 -preset slow -crf 20 -pix_fmt yuv420p -movflags +faststart build/hero/ascii-racer-reel.mp4

ls -la docs/images/hero.gif docs/images/logo.png build/hero/ascii-racer-reel.mp4 | awk '{printf "%10d  %s\n", $5, $9}'
