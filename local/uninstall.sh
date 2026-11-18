#!/bin/bash
# Stop and remove the Mac's background jobs (the files in this folder stay).
for job in render serve; do
  launchctl bootout "gui/$(id -u)/local.kindleweather.$job" >/dev/null 2>&1
  rm -f "$HOME/Library/LaunchAgents/local.kindleweather.$job.plist"
done
echo "Stopped. The Kindle will show its no-connection notice until it has a source again."
