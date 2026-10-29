#!/bin/sh
# Weather dashboard loop for a jailbroken Kindle Paperwhite 3.
# Stops the normal Kindle UI, keeps the screen awake, checks for a new dash.png every few
# minutes, plays the split-flap animation if the temperatures changed, then redraws.
# To get back to the normal Kindle: hold the power button until it restarts (~40 s).
trap '' HUP TERM   # survive KUAL/UI shutdown
. /mnt/us/extensions/weatherdash/bin/lib.sh
. "$DIR/config.sh"
IMG="$DIR/dash.png"
TMP="$DIR/dash.tmp"
LOG="$DIR/dash.log"
BASE="${IMAGE_URL%/*}"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }

wait_wifi() {
  i=0
  while [ $i -lt 45 ]; do
    [ "$(lipc-get-prop com.lab126.wifid cmState 2>/dev/null)" = "CONNECTED" ] && return 0
    [ $i -eq 5 ] && lipc-set-prop com.lab126.cmd wirelessEnable 1 2>/dev/null
    sleep 2; i=$((i + 1))
  done
  return 1
}

fetch_image() {
  rm -f "$TMP"
  get "$IMAGE_URL" "$TMP" && [ -s "$TMP" ] && head -c 8 "$TMP" | grep -q PNG
}

fetch_anim() {     # $1 = md5 of the new dash.png; frames must belong to that exact image
  A="$DIR/anim"; mkdir -p "$A"; rm -f "$A"/*
  get "$BASE/anim/anim.txt" "$A/anim.txt" || return 1
  [ "$(sed -n 's/^id //p' "$A/anim.txt")" = "$1" ] || return 1
  grep -q '^f' "$A/anim.txt" || return 1
  while read -r name x y; do
    [ "$name" = "id" ] && continue
    [ -n "$y" ] || continue
    get "$BASE/anim/$name" "$A/$name" || return 1
  done < "$A/anim.txt"
}

# keep the log small
[ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 200000 ] && tail -c 50000 "$LOG" > "$LOG.old" && mv "$LOG.old" "$LOG"

log "starting; url=$IMAGE_URL every ${REFRESH_MINUTES}m"
lipc-set-prop com.lab126.powerd preventScreenSaver 1
sleep 3
stop lab126_gui 2>/dev/null && log "stopped lab126_gui"
stop framework 2>/dev/null && log "stopped framework"
[ -x /etc/init.d/framework ] && /etc/init.d/framework stop >/dev/null 2>&1 && log "stopped framework (init.d)"
initctl stop webreader >/dev/null 2>&1
lipc-set-prop com.lab126.powerd preventScreenSaver 1
trap - TERM
sleep 2

if [ -s "$IMG" ]; then draw_full "$IMG"; else "$FBINK" -q -c -f -m -y 20 "Starting weather dashboard..." 2>/dev/null; fi
last="$( [ -s "$IMG" ] && md5sum "$IMG" | cut -d' ' -f1 )"
fails=0
while true; do
  if wait_wifi && fetch_image; then
    sum="$(md5sum "$TMP" | cut -d' ' -f1)"
    if [ "$sum" != "$last" ] || [ $fails -gt 1 ]; then
      if [ -n "$last" ] && fetch_anim "$sum"; then play_frames "$DIR/anim" && log "flipped"; fi
      mv "$TMP" "$IMG"
      draw_full "$IMG"; last="$sum"; log "drew new image"
    fi
    fails=0
  else
    fails=$((fails + 1))
    log "update failed ($fails); wifi=$(lipc-get-prop com.lab126.wifid cmState 2>/dev/null)"
    [ $fails -eq 2 ] && msg "No connection - showing last forecast, retrying"
  fi
  batt="$(lipc-get-prop com.lab126.powerd battLevel 2>/dev/null)"
  chg="$(lipc-get-prop com.lab126.powerd isCharging 2>/dev/null)"
  if [ -n "$batt" ] && [ "$batt" -lt 15 ] && [ "$chg" != "1" ]; then msg "Battery ${batt}% - please plug in"; fi
  sleep $((REFRESH_MINUTES * 60))
done
