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

fetch_show() {     # prefetch the coming on-the-hour board show into $DIR/show (if it's new)
  S="$DIR/show.new"; rm -rf "$S"; mkdir -p "$S"
  get "$BASE/show/show.txt?t=$(date +%s)" "$S/show.txt" || return 1
  h="$(sed -n 's/^hour //p' "$S/show.txt")"
  [ -n "$h" ] && [ "$h" != "none" ] || { rm -rf "$DIR/show"; return 1; }
  [ -f "$DIR/show/show.txt" ] && [ "$(sed -n 's/^hour //p' "$DIR/show/show.txt")" = "$h" ] && return 0
  while read -r kind name rest; do
    case "$kind" in start|frame|final) get "$BASE/show/$name" "$S/$name" || return 1 ;; esac
  done < "$S/show.txt"
  rm -rf "$DIR/show"; mv "$S" "$DIR/show"
}

play_show() {      # the departure board: blank board, tiles clatter, settle, hold, back to weather
  S="$DIR/show"
  draw_full "$S/$(sed -n 's/^start //p' "$S/show.txt")"
  while read -r kind name x y; do
    [ "$kind" = "frame" ] || continue
    "$FBINK" -q -W A2 -g file="$S/$name",x="$x",y="$y" 2>/dev/null
    usleep 30000 2>/dev/null
  done < "$S/show.txt"
  draw_full "$S/$(sed -n 's/^final //p' "$S/show.txt")"
  hold="$(sed -n 's/^hold //p' "$S/show.txt")"
  sleep "${hold:-20}"
  draw_full "$IMG"
}

show_hour() { sed -n 's/^hour //p' "$DIR/show/show.txt" 2>/dev/null; }

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
shown=""
while true; do
  # on the hour: the departure-board show (Kindle's clock is right in UTC; Hobart is a whole
  # number of hours off UTC, so UTC minute 00 is Hobart's top of the hour too)
  H="$(date -u +%Y%m%d%H)"; MIN="$(date -u +%M | sed 's/^0//')"; MIN="${MIN:-0}"
  if [ "$MIN" -ge 50 ]; then fetch_show; fi
  if [ "$MIN" -le 3 ] && [ "$shown" != "$H" ]; then
    [ "$(show_hour)" = "$H" ] || fetch_show
    if [ "$(show_hour)" = "$H" ] && [ -s "$IMG" ]; then
      play_show; shown="$H"; partials=0; set_light "${LIGHT:-16}"; log "hourly board show"
    fi
  fi

  # every ten minutes (at :05, :15, ...): install newer dashboard code from GitHub, then restart
  if [ $(( MIN % 10 )) -eq 5 ] && sh "$DIR/bin/selfupdate.sh" >> "$LOG" 2>&1; then
    log "restarting on new code"
    exec /bin/sh "$DIR/bin/dash.sh"
  fi

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
  sec="$(date -u +%S | sed 's/^0//')"            # wake on the minute, so the show starts on time
  sleep $(( REFRESH_MINUTES * 60 - ${sec:-0} ))
done
