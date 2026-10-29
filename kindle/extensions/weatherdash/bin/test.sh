#!/bin/sh
# One-off check: writes a diagnostic report, then runs through every kind of screen update
# the dashboard uses, on the sample screen (landscape, charging port on the left).
. /mnt/us/extensions/weatherdash/bin/lib.sh
LOG="$DIR/test.log"
{
  echo "=== weatherdash test $(date)"
  echo "--- eips -i";   eips -i 2>&1 | grep -E "xres|yres|rotate|bits_per|DPI"
  echo "--- fbink -v";  "$FBINK" -v 2>&1 | head -5
  echo "--- wifi";      lipc-get-prop com.lab126.wifid cmState 2>&1
  echo "--- battery";   lipc-get-prop com.lab126.powerd battLevel 2>&1
  . "$DIR/config.sh"
  echo "--- light (setting ${LIGHT:-16}/24)"
  set_light "${LIGHT:-16}"
  echo "powerd flIntensity=$(lipc-get-prop com.lab126.powerd flIntensity 2>&1)"
  for b in /sys/class/backlight/*/brightness; do echo "$b=$(cat "$b" 2>&1) max=$(cat "${b%/brightness}/max_brightness" 2>&1)"; done
  echo "--- https";     curl -sS -m 25 -o /dev/null -w "%{http_code}\n" https://abrett-arch.github.io/kindle-weather/dash.png 2>&1
  sleep 3   # let KUAL finish closing so its redraw doesn't paint over us

  echo "--- stage 1: full screen (fbink, flashing)"
  t0=$(uptime_ms); out=$("$FBINK" -c -f -g file="$DIR/demo/start.png" 2>&1); rc=$?; t1=$(uptime_ms)
  echo "$out" | head -3; echo "exit=$rc ms=$((t1 - t0))"
  if [ $rc -ne 0 ]; then
    t0=$(uptime_ms); eips -f -g "$DIR/demo/start.png" 2>&1; rc=$?; t1=$(uptime_ms)
    echo "eips fallback exit=$rc ms=$((t1 - t0))"
  fi
  sleep 4

  echo "--- stage 2: flip frames (A2)"
  t0=$(uptime_ms); n=0; rc=0
  while read -r name x y; do
    [ -n "$y" ] || continue
    out=$("$FBINK" -W A2 -g file="$DIR/demo/$name",x="$x",y="$y" 2>&1); r=$?
    [ $n -eq 0 ] && echo "$out" | head -3
    [ $r -ne 0 ] && rc=$r
    n=$((n + 1)); usleep 40000
  done < "$DIR/demo/anim.txt"
  t1=$(uptime_ms); echo "frames=$n ms=$((t1 - t0)) worst_exit=$rc"

  echo "--- stage 3: tile area only, local flash"
  read -r x y < "$DIR/demo/tiles.txt"
  out=$("$FBINK" -f -g file="$DIR/demo/tiles.png",x="$x",y="$y" 2>&1); rc=$?; echo "$out" | head -2; echo "exit=$rc"
  sleep 3

  echo "--- stage 4: no-flash region (REAGL, then GL16)"
  read -r bx by < "$DIR/banner.txt"
  out=$("$FBINK" -W REAGL -g file="$DIR/offline.png",x="$bx",y="$by" 2>&1); rc=$?
  echo "$out" | head -2; echo "REAGL exit=$rc"
  if [ $rc -ne 0 ]; then out=$("$FBINK" -W GL16 -g file="$DIR/offline.png",x="$bx",y="$by" 2>&1); rc=$?; echo "$out" | head -2; echo "GL16 exit=$rc"; fi
  sleep 4

  echo "--- stage 5: final full refresh"
  "$FBINK" -c -f -g file="$DIR/sample.png" >/dev/null 2>&1; echo "exit=$?"
  echo "=== done"
} > "$LOG" 2>&1
