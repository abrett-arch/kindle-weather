#!/bin/sh
# Launch the dashboard loop detached from KUAL (KUAL dies when the Kindle UI is stopped).
DIR=/mnt/us/extensions/weatherdash
if command -v setsid >/dev/null 2>&1; then
  setsid /bin/sh "$DIR/bin/dash.sh" >> "$DIR/dash.log" 2>&1 < /dev/null &
else
  nohup /bin/sh "$DIR/bin/dash.sh" >> "$DIR/dash.log" 2>&1 < /dev/null &
fi
