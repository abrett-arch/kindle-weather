#!/bin/sh
# Launch the dashboard loop detached from KUAL (KUAL dies when the Kindle UI is stopped).
DIR=/mnt/us/extensions/weatherdash
pid="$(cat "$DIR/dash.pid" 2>/dev/null)"
if [ -n "$pid" ] && grep -q dash.sh "/proc/$pid/cmdline" 2>/dev/null; then
  exit 0                                   # already running
fi
if command -v setsid >/dev/null 2>&1; then
  setsid /bin/sh "$DIR/bin/dash.sh" >> "$DIR/dash.log" 2>&1 < /dev/null &
else
  nohup /bin/sh "$DIR/bin/dash.sh" >> "$DIR/dash.log" 2>&1 < /dev/null &
fi
