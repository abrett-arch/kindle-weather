#!/bin/sh
# Play the latest published on-the-hour board show right now, then show the live weather.
. /mnt/us/extensions/weatherdash/bin/lib.sh
. "$DIR/config.sh"
BASE="${IMAGE_URL%/*}"
LOG="$DIR/preview.log"
S="$DIR/show.preview"
{
  echo "=== board preview $(date -u)"
  rm -rf "$S"; mkdir -p "$S"
  get "$BASE/show/show.txt?t=$(date +%s)" "$S/show.txt" || { echo "no show.txt"; exit 1; }
  if grep -q '^hour none' "$S/show.txt"; then echo "a message is showing; no board"; exit 0; fi
  n=0
  while read -r kind name rest; do
    case "$kind" in start|frame|final) get "$BASE/show/$name" "$S/$name" || { echo "failed $name"; exit 1; }; n=$((n + 1)) ;; esac
  done < "$S/show.txt"
  echo "downloaded $n files"
  get "$IMAGE_URL" "$S/dash.png"
  sleep 2   # let KUAL close first
  t0=$(uptime_ms)
  draw_full "$S/$(sed -n 's/^start //p' "$S/show.txt")"
  while read -r kind name x y; do
    [ "$kind" = "frame" ] || continue
    "$FBINK" -q -W A2 -g file="$S/$name",x="$x",y="$y" 2>/dev/null
    usleep 30000
  done < "$S/show.txt"
  t1=$(uptime_ms); echo "clatter ms: $((t1 - t0))"
  draw_full "$S/$(sed -n 's/^final //p' "$S/show.txt")"
  sleep 12
  if [ -s "$S/dash.png" ]; then draw_full "$S/dash.png"; else draw_full "$DIR/sample.png"; fi
  echo "=== done"
} > "$LOG" 2>&1
