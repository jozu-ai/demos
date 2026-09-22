#!/usr/bin/env bash
#
# Renders mcp-trust.tape to mcp-trust-demo.mp4.
#
# Why this exists instead of just `vhs mcp-trust.tape`: vhs 0.12.0 with
# ffmpeg 9 renders every frame into a temp directory but never runs its
# encode step, then deletes the frames and exits 0 having written no file.
# So we mirror the frames out while vhs is still running and encode them
# ourselves. The recording is still entirely vhs's - only the last step is
# ours. If a future vhs writes the .mp4 on its own, delete this script.

set -euo pipefail
cd "$(dirname "$0")"

TAPE="mcp-trust.tape"
OUT="mcp-trust-demo.mp4"

# Match the encode to what the tape asked the terminal to be.
FPS=$(awk '/^Set Framerate/ {print $3}' "$TAPE"); FPS=${FPS:-50}
WIDTH=$(awk '/^Set Width/ {print $3}' "$TAPE")
HEIGHT=$(awk '/^Set Height/ {print $3}' "$TAPE")
BG=0x1e1e2e   # Catppuccin Mocha background, so the padding is invisible

TMP="${TMPDIR:-/tmp}"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

printf 'Recording (this runs the demo for real, ~3 minutes)...\n'
vhs "$TAPE" >/dev/null 2>&1 &
VHS_PID=$!

# vhs writes frame-text-NNNNN.png and frame-cursor-NNNNN.png into $TMPDIR/vhsNNNN
# (its Chrome profile is the similarly named vhs-NNNN, hence the [0-9] anchor).
while kill -0 "$VHS_PID" 2>/dev/null; do
  FRAMES=$(find "$TMP" -maxdepth 1 -type d -name 'vhs[0-9]*' 2>/dev/null | head -1)
  [ -n "$FRAMES" ] && rsync -a --ignore-existing "$FRAMES"/ "$STAGE"/ 2>/dev/null || true
  sleep 0.5
done
wait "$VHS_PID" 2>/dev/null || true

# The mirror can miss the last fraction of a second, and rsync does not copy in
# index order, so take the highest frame number with no gap below it - in both
# layers - rather than letting ffmpeg walk into a hole. The encode stops one
# frame short of that, because the image2 demuxer reads one ahead of the last
# frame it emits and complains out loud when that one is missing.
contiguous() {
  ls "$STAGE" 2>/dev/null | sed -n "s/^frame-$1-\([0-9]*\)\.png$/\1/p" | sort -n |
    awk '{ if ($1+0 != NR) { print NR-1; found=1; exit } } END { if (!found) print NR }'
}
COUNT=$(contiguous text)
CURSORS=$(contiguous cursor)
[ "$CURSORS" -lt "$COUNT" ] && COUNT=$CURSORS

if [ "${COUNT:-0}" -eq 0 ]; then
  printf 'No frames captured. Is vhs installed and did the tape run?\n' >&2
  exit 1
fi
printf 'Captured %s frames at %s fps. Encoding...\n' "$COUNT" "$FPS"

# The cursor is a separate layer vhs composites on top of the text layer.
# Frames cover the terminal only, so pad back out to the tape's dimensions.
# crf 16 and a 2-second keyframe interval because YouTube re-encodes whatever
# it is given, and text is what suffers first. The silent AAC track is there
# because a video-only upload is the one thing YouTube's pipeline is flaky about.
ffmpeg -y -loglevel error \
  -framerate "$FPS" -start_number 1 -i "$STAGE/frame-text-%05d.png" \
  -framerate "$FPS" -start_number 1 -i "$STAGE/frame-cursor-%05d.png" \
  -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=48000 \
  -filter_complex "[0:v][1:v]overlay=format=auto,pad=${WIDTH}:${HEIGHT}:(ow-iw)/2:(oh-ih)/2:${BG},format=yuv420p[v]" \
  -map "[v]" -map 2:a -frames:v "$((COUNT - 1))" \
  -c:v libx264 -crf 16 -preset medium -g 60 \
  -c:a aac -b:a 128k -shortest \
  -movflags +faststart "$OUT"

printf '\n%s  (%s)\n' "$OUT" "$(du -h "$OUT" | cut -f1)"
