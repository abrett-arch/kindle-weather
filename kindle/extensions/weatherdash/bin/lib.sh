# Shared helpers for the weather dashboard scripts.
DIR=/mnt/us/extensions/weatherdash
FBINK=/mnt/us/libkh/bin/fbink

draw_full() {      # whole screen, flashing refresh (clears e-ink ghosting)
  "$FBINK" -q -c -f -g file="$1" 2>/dev/null || eips -f -g "$1"
}

play_frames() {    # $1 = folder holding anim.txt + frame PNGs; fast black/white partial updates
  [ -s "$1/anim.txt" ] || return 1
  while read -r name x y; do
    [ "$name" = "id" ] && continue
    [ -n "$y" ] || continue
    "$FBINK" -q -W A2 -g file="$1/$name",x="$x",y="$y" 2>/dev/null || return 1
    usleep 40000 2>/dev/null
  done < "$1/anim.txt"
}

msg() {            # one line of text near the bottom of the screen
  "$FBINK" -q -m -y -3 "$1" 2>/dev/null || eips 2 38 "$1"
}

get() {            # get URL FILE  (verified TLS, then unverified, then wget)
  curl -fsS -m 60 -o "$2" "$1" 2>/dev/null \
    || curl -fsSk -m 60 -o "$2" "$1" 2>/dev/null \
    || wget -q -T 60 -O "$2" "$1" 2>/dev/null
}

uptime_ms() { awk '{printf "%d", $1 * 1000}' /proc/uptime; }
