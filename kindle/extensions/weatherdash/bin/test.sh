#!/bin/sh
# One-off check: writes a diagnostic report, then shows the sample screen with a demo flip.
. /mnt/us/extensions/weatherdash/bin/lib.sh
LOG="$DIR/test.log"
{
  echo "=== weatherdash test $(date)"
  echo "--- eips -i";   eips -i 2>&1 | grep -E "xres|yres|rotate|bits_per|DPI|waveform"
  echo "--- fbink -v";  "$FBINK" -v 2>&1 | head -5; echo "exit=$?"
  echo "--- tools";     for t in curl wget setsid usleep md5sum; do printf '%s: ' "$t"; command -v "$t" || echo missing; done
  echo "--- wifi";      lipc-get-prop com.lab126.wifid cmState 2>&1
  echo "--- battery";   lipc-get-prop com.lab126.powerd battLevel 2>&1
  echo "--- https";     curl -sS -m 25 -o /dev/null -w "%{http_code}\n" https://abrett-arch.github.io/kindle-weather/dash.png 2>&1
  sleep 3   # let KUAL finish closing so its redraw doesn't paint over us

  echo "--- stage 1: full screen with fbink"
  t0=$(uptime_ms); "$FBINK" -c -f -g file="$DIR/demo/start.png" 2>&1; rc=$?; t1=$(uptime_ms)
  echo "fbink exit=$rc ms=$((t1 - t0))"
  if [ $rc -ne 0 ]; then
    echo "--- stage 1b: full screen with eips"
    t0=$(uptime_ms); eips -f -g "$DIR/demo/start.png" 2>&1; rc=$?; t1=$(uptime_ms)
    echo "eips exit=$rc ms=$((t1 - t0))"
  fi
  sleep 4

  echo "--- stage 2: flip frames (fbink, A2 waveform)"
  t0=$(uptime_ms); n=0
  while read -r name x y; do
    [ -n "$y" ] || continue
    out=$("$FBINK" -W A2 -g file="$DIR/demo/$name",x="$x",y="$y" 2>&1); rc=$?
    [ $n -eq 0 ] && echo "$out" | head -3
    n=$((n + 1)); usleep 40000
  done < "$DIR/demo/anim.txt"
  t1=$(uptime_ms); echo "frames=$n ms=$((t1 - t0)) last_exit=$rc"
  sleep 3

  echo "--- stage 3: final full refresh"
  "$FBINK" -c -f -g file="$DIR/sample.png" 2>&1; echo "fbink exit=$?"
  echo "=== done"
} > "$LOG" 2>&1
