#!/bin/sh
# One-off check: writes a diagnostic report, then shows the sample screen with a demo flip.
. /mnt/us/extensions/weatherdash/bin/lib.sh
LOG="$DIR/test.log"
{
  echo "=== weatherdash test $(date)"
  echo "--- eips -i";   eips -i 2>&1
  echo "--- fbink -e";  "$FBINK" -e 2>&1
  echo "--- uname";     uname -a
  echo "--- version";   cat /etc/version.txt /etc/prettyversion.txt 2>&1
  echo "--- tools";     for t in curl wget setsid nohup md5sum usleep awk sed rtcwake; do printf '%s: ' "$t"; command -v "$t" || echo missing; done
  echo "--- curl -V";   curl -V 2>&1 | head -3
  echo "--- jobs";      initctl list 2>&1 | grep -i -E "framework|lab126_gui|webreader|wifid|cmd|powerd"; ls /etc/init.d 2>&1 | tr '\n' ' '; echo
  echo "--- wifi";      lipc-get-prop com.lab126.wifid cmState 2>&1
  echo "--- battery";   lipc-get-prop com.lab126.powerd battLevel 2>&1; lipc-get-prop com.lab126.powerd isCharging 2>&1
  echo "--- date";      date
  echo "--- https (verified)";   curl -sS -m 25 -o /dev/null -w "%{http_code}\n" https://github.com/ 2>&1
  echo "--- https (unverified)"; curl -sSk -m 25 -o /dev/null -w "%{http_code}\n" https://github.com/ 2>&1
  echo "--- draw"
  sleep 3   # let KUAL finish closing so its redraw doesn't paint over us
  t0=$(uptime_ms); draw_full "$DIR/demo/start.png"; t1=$(uptime_ms)
  echo "full draw ms: $((t1 - t0))"
  sleep 2
  t0=$(uptime_ms)
  if play_frames "$DIR/demo"; then t1=$(uptime_ms); echo "flip ok, 8 frames ms: $((t1 - t0))"
  else echo "flip FAILED"; fi
  sleep 1
  draw_full "$DIR/sample.png"
  echo "=== done"
} > "$LOG" 2>&1
