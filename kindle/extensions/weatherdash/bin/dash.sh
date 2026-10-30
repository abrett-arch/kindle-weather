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

fetch_image() {    # downloads the image named by $v (cache-busted so we never get an old copy)
  rm -f "$TMP"
  get "$IMAGE_URL?v=$v" "$TMP" && [ -s "$TMP" ] && head -c 8 "$TMP" | grep -q PNG
}

fetch_delta() {    # $1 = md5 of the new dash.png. Succeeds if the in-place update applies to
                   # exactly what is on screen now ($last) and every piece downloaded.
  D="$DIR/delta"; mkdir -p "$D"; rm -f "$D"/*
  get "$BASE/delta/update.txt?v=$1" "$D/update.txt" || return 1
  [ "$(sed -n 's/^id //p' "$D/update.txt")" = "$1" ] || return 1
  [ "$(sed -n 's/^base //p' "$D/update.txt")" = "$last" ] || return 1
  while read -r kind name rest; do
    case "$kind" in frame|region) get "$BASE/delta/$name?v=$1" "$D/$name" || return 1 ;; esac
  done < "$D/update.txt"
}

fetch_show() {     # prefetch the coming on-the-hour board show into $DIR/show (if it's new)
  S="$DIR/show.new"; rm -rf "$S"; mkdir -p "$S"
  get "$BASE/show/show.txt?t=$(date +%s)" "$S/show.txt" || return 1
  h="$(sed -n 's/^hour //p' "$S/show.txt")"
  [ -n "$h" ] && [ "$h" != "none" ] || { rm -rf "$DIR/show"; return 1; }
  [ -f "$DIR/show/show.txt" ] && [ "$(sed -n 's/^hour //p' "$DIR/show/show.txt")" = "$h" ] && return 0
  while read -r kind name rest; do
    case "$kind" in start|frame|final) get "$BASE/show/$name?h=$h" "$S/$name" || return 1 ;; esac
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

apply_update() {   # $TMP holds the new image (md5 $v): flip, then patch in place or redraw
  mode=full
  if [ -n "$last" ] && [ "$banner_up" = "" ] && fetch_delta "$v"; then
    grep -q '^frame' "$DIR/delta/update.txt" && play_frames "$DIR/delta" && log "flipped"
    grep -q '^region' "$DIR/delta/update.txt" && [ $partials -lt $FULL_EVERY ] && mode=partial
  fi
  mv -f "$TMP" "$IMG"
  if [ $mode = partial ]; then
    while read -r kind name x y how; do
      [ "$kind" = "region" ] && draw_region "$DIR/delta/$name" "$x" "$y" "$how"
    done < "$DIR/delta/update.txt"
    partials=$((partials + 1)); log "updated in place ($partials)"
  else
    draw_full "$IMG"; partials=0; log "full redraw"
  fi
  last="$v"; banner_up=""
}

trim_log() {       # keep the log under ~200 KB (truncate in place: stdout stays attached)
  if [ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 200000 ]; then
    tail -c 50000 "$LOG" > "$LOG.old" && cat "$LOG.old" > "$LOG"; rm -f "$LOG.old"
  fi
}

echo $$ > "$DIR/dash.pid"          # start.sh uses this to avoid running two loops
trim_log
log "starting; url=$IMAGE_URL every ${REFRESH_MINUTES}m"
lipc-set-prop com.lab126.powerd preventScreenSaver 1
sleep 3
stop lab126_gui 2>/dev/null && log "stopped lab126_gui"
stop framework 2>/dev/null && log "stopped framework"
[ -x /etc/init.d/framework ] && /etc/init.d/framework stop >/dev/null 2>&1 && log "stopped framework (init.d)"
initctl stop webreader >/dev/null 2>&1
lipc-set-prop com.lab126.powerd preventScreenSaver 1
set_light "${LIGHT:-16}" && log "light ${LIGHT:-16}/24"
for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do   # idle most of the time: save power
  [ -w "$g" ] && echo powersave > "$g" 2>/dev/null && log "cpu governor powersave"
done
trap - TERM
sleep 2

if [ -s "$IMG" ]; then draw_full "$IMG"; else "$FBINK" -q -c -f -m -y 20 "Starting weather dashboard..." 2>/dev/null; fi
last="$( [ -s "$IMG" ] && md5sum "$IMG" | cut -d' ' -f1 )"
fails=0           # consecutive minutes without a connection
partials=0        # in-place updates since the last full-screen clean-up
FULL_EVERY=12     # full flash refresh after this many in-place updates (~3 hours)
banner_up=""      # a notice is on screen: the next good update redraws everything
shown=""; updated_slot=""; batt_slot=""; trim_hour=""
while true; do
  H="$(date -u +%Y%m%d%H)"; MIN="$(date -u +%M | sed 's/^0//')"; MIN="${MIN:-0}"
  online=""; wait_wifi && online=1

  # on the hour: the departure-board show (the Kindle's clock is right in UTC, and Hobart is
  # a whole number of hours off UTC, so UTC minute 00 is Hobart's top of the hour too)
  if [ -n "$online" ] && [ "$MIN" -ge 50 ]; then fetch_show; fi
  if [ "$MIN" -le 3 ] && [ "$shown" != "$H" ]; then
    [ "$(show_hour)" = "$H" ] || { [ -n "$online" ] && fetch_show; }
    if [ "$(show_hour)" = "$H" ] && [ -s "$IMG" ]; then
      play_show; shown="$H"; partials=0; banner_up=""; set_light "${LIGHT:-16}"; log "hourly board show"
    fi
  fi

  # every ten minutes (at :05, :15, ...): install newer dashboard code from GitHub, then restart.
  # The updater runs from a copy, so it can safely replace its own file.
  slot="$H$(( MIN / 10 ))"
  if [ -n "$online" ] && [ $(( MIN % 10 )) -ge 5 ] && [ "$slot" != "$updated_slot" ]; then
    updated_slot="$slot"
    cp -f "$DIR/bin/selfupdate.sh" "$DIR/selfupdate.run" 2>/dev/null
    if sh "$DIR/selfupdate.run" >> "$LOG" 2>&1; then
      log "restarting on new code"
      exec /bin/sh "$DIR/bin/dash.sh"
    fi
  fi

  if [ -n "$online" ] && check_version; then
    fails=0
    if [ "$v" != "$last" ] || [ -n "$banner_up" ]; then
      if [ "$v" = "$last" ] && [ -s "$IMG" ]; then
        draw_full "$IMG"; banner_up=""; partials=0; log "cleared notice"
      elif fetch_image; then
        if [ "$(md5sum "$TMP" | cut -d' ' -f1)" = "$v" ]; then apply_update
        else rm -f "$TMP"; log "got an out-of-date copy; will try again next minute"; fi
      else
        log "image download failed"
      fi
    fi
    set_light "${LIGHT:-16}"
  else
    fails=$((fails + 1))
    log "no connection ($fails); wifi=$(lipc-get-prop com.lab126.wifid cmState 2>/dev/null)"
    [ $fails -eq 2 ] && banner offline.png && banner_up=1
  fi
  batt="$(lipc-get-prop com.lab126.powerd battLevel 2>/dev/null)"
  chg="$(lipc-get-prop com.lab126.powerd isCharging 2>/dev/null)"
  if [ "$H$(( MIN / 15 ))" != "$batt_slot" ]; then  # battery log, read over USB: time,level,charging
    batt_slot="$H$(( MIN / 15 ))"
    echo "$(date -u '+%Y-%m-%dT%H:%MZ'),${batt:-?},${chg:-?}" >> "$DIR/battery.csv"
    [ "$(wc -l < "$DIR/battery.csv")" -gt 3000 ] && tail -n 2000 "$DIR/battery.csv" > "$DIR/battery.tmp" && cat "$DIR/battery.tmp" > "$DIR/battery.csv"
  fi
  if [ -n "$batt" ] && [ "$batt" -lt 20 ] && [ "$chg" != "1" ]; then
    [ -z "$banner_up" ] && banner battery.png && banner_up=1
  fi
  [ "$H" != "$trim_hour" ] && trim_hour="$H" && trim_log
  # on battery, check less often, except around the hour so the board starts on time
  every="$REFRESH_MINUTES"
  if [ "$chg" != "1" ] && [ "$MIN" -ge 4 ] && [ "$MIN" -lt 47 ]; then every="${BATTERY_REFRESH_MINUTES:-3}"; fi
  sec="$(date -u +%S | sed 's/^0//')"            # wake on the minute, so the show starts on time
  sleep $(( every * 60 - ${sec:-0} ))
done
