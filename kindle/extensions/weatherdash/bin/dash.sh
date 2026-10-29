#!/bin/sh
# Weather dashboard loop for a jailbroken Kindle Paperwhite 3.
# Stops the normal Kindle UI, keeps the screen awake, checks for a new dash.png every few
# minutes, plays the split-flap animation if the temperatures changed, then redraws only
# the parts of the screen that changed (with a full clean-up refresh every few hours).
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

check_version() {  # sets $v to the md5 of the currently published dash.png
  get "$BASE/version.txt?t=$(date +%s)" "$DIR/version.new" || return 1
  v="$(cut -c1-32 "$DIR/version.new")"
  [ ${#v} -eq 32 ]
}

fetch_image() {
  rm -f "$TMP"
  get "$IMAGE_URL" "$TMP" && [ -s "$TMP" ] && head -c 8 "$TMP" | grep -q PNG
}

fetch_delta() {    # $1 = md5 of the new dash.png. Succeeds if the in-place update applies to
                   # exactly what is on screen now ($last) and every piece downloaded.
  D="$DIR/delta"; mkdir -p "$D"; rm -f "$D"/*
  get "$BASE/delta/update.txt" "$D/update.txt" || return 1
  [ "$(sed -n 's/^id //p' "$D/update.txt")" = "$1" ] || return 1
  [ "$(sed -n 's/^base //p' "$D/update.txt")" = "$last" ] || return 1
  while read -r kind name rest; do
    case "$kind" in frame|region) get "$BASE/delta/$name" "$D/$name" || return 1 ;; esac
  done < "$D/update.txt"
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
set_light "${LIGHT:-16}" && log "light ${LIGHT:-16}/24"
trap - TERM
sleep 2

if [ -s "$IMG" ]; then draw_full "$IMG"; else "$FBINK" -q -c -f -m -y 20 "Starting weather dashboard..." 2>/dev/null; fi
last="$( [ -s "$IMG" ] && md5sum "$IMG" | cut -d' ' -f1 )"
fails=0
partials=0        # in-place updates since the last full-screen clean-up
FULL_EVERY=12     # full flash refresh after this many in-place updates (~3 hours)
while true; do
  if wait_wifi && check_version; then
    if { [ "$v" != "$last" ] || [ $fails -gt 1 ]; } && fetch_image; then
      sum="$(md5sum "$TMP" | cut -d' ' -f1)"
      mode=full
      if [ -n "$last" ] && [ $fails -le 1 ] && fetch_delta "$sum"; then
        grep -q '^frame' "$DIR/delta/update.txt" && play_frames "$DIR/delta" && log "flipped"
        grep -q '^region' "$DIR/delta/update.txt" && [ $partials -lt $FULL_EVERY ] && mode=partial
      fi
      mv "$TMP" "$IMG"
      if [ $mode = partial ]; then
        while read -r kind name x y how; do
          [ "$kind" = "region" ] && draw_region "$DIR/delta/$name" "$x" "$y" "$how"
        done < "$DIR/delta/update.txt"
        partials=$((partials + 1)); log "updated in place ($partials)"
      else
        draw_full "$IMG"; partials=0; log "full redraw"
      fi
      last="$sum"
    fi
    fails=0
    set_light "${LIGHT:-16}"
  else
    fails=$((fails + 1))
    log "update failed ($fails); wifi=$(lipc-get-prop com.lab126.wifid cmState 2>/dev/null)"
    [ $fails -eq 2 ] && banner offline.png
  fi
  batt="$(lipc-get-prop com.lab126.powerd battLevel 2>/dev/null)"
  chg="$(lipc-get-prop com.lab126.powerd isCharging 2>/dev/null)"
  if [ -n "$batt" ] && [ "$batt" -lt 15 ] && [ "$chg" != "1" ]; then banner battery.png; fi
  sleep $((REFRESH_MINUTES * 60))
done
