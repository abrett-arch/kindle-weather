# Shared helpers for the weather dashboard scripts.
DIR=/mnt/us/extensions/weatherdash
FBINK=/mnt/us/libkh/bin/fbink

draw_full() {      # whole screen, flashing refresh (clears e-ink ghosting)
  "$FBINK" -q -c -f -g file="$1" 2>/dev/null || eips -f -g "$1"
}

play_frames() {    # $1 = folder holding update.txt + frames; fast black/white partial updates
  [ -s "$1/update.txt" ] || return 1
  while read -r kind name x y rest; do
    [ "$kind" = "frame" ] || continue
    "$FBINK" -q -W A2 -g file="$1/$name",x="$x",y="$y" 2>/dev/null || return 1
    usleep 40000 2>/dev/null
  done < "$1/update.txt"
}

draw_region() {    # file x y flash|calm : redraw one rectangle in place
  if [ "$4" = "flash" ]; then
    "$FBINK" -q -f -g file="$1",x="$2",y="$3" 2>/dev/null && return 0
  else
    "$FBINK" -q -W REAGL -g file="$1",x="$2",y="$3" 2>/dev/null && return 0
    "$FBINK" -q -W GL16 -g file="$1",x="$2",y="$3" 2>/dev/null && return 0
    "$FBINK" -q -g file="$1",x="$2",y="$3" 2>/dev/null && return 0
  fi
  eips -g "$1" -x "$2" -y "$3" >/dev/null 2>&1
}

banner() {         # offline.png | battery.png : pre-drawn notice over the header's right side
  read -r bx by < "$DIR/banner.txt" && draw_region "$DIR/$1" "$bx" "$by" calm
}

get() {            # get URL FILE  (verified TLS only: the Kindle installs code this way)
  curl -fsS --connect-timeout 15 -m 90 -o "$2" "$1" 2>/dev/null
}

set_light() {      # $1 = 0..24 (same scale as the Kindle's light slider)
  lipc-set-prop com.lab126.powerd flIntensity "$1" 2>/dev/null
  for b in /sys/class/backlight/*/brightness; do      # belt and braces if powerd ignores it
    [ -w "$b" ] || continue
    max=$(cat "${b%/brightness}/max_brightness" 2>/dev/null)
    [ -n "$max" ] && echo $(( $1 * max / 24 )) > "$b" 2>/dev/null
  done
}

uptime_ms() { awk '{printf "%d", $1 * 1000}' /proc/uptime; }
