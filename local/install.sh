#!/bin/bash
# One-off setup on the Mac: Python, the two background jobs, and the Kindle's address.
# Safe to run again (e.g. if the Mac's address on the home network changes).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
AGENTS="$HOME/Library/LaunchAgents"; UID_N="$(id -u)"
KCFG="$ROOT/kindle/extensions/weatherdash/config.sh"
say() { printf '\n\033[1m%s\033[0m\n' "$*"; }

say "1/5  Python"
PYBIN=""
for p in python3.13 python3.12 python3.11 python3.10 python3; do
  if command -v "$p" >/dev/null 2>&1 && "$p" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)' >/dev/null 2>&1; then
    PYBIN="$(command -v "$p")"; break
  fi
done
if [ -n "$PYBIN" ]; then
  echo "using $PYBIN ($("$PYBIN" --version 2>&1))"
  [ -x .venv/bin/python ] || "$PYBIN" -m venv .venv
else
  echo "No usable Python found; installing a private copy with uv (from astral.sh)."
  command -v uv >/dev/null 2>&1 || curl -LsSf https://astral.sh/uv/install.sh | sh
  UV="$(command -v uv || echo "$HOME/.local/bin/uv")"
  "$UV" venv --python 3.12 .venv
fi
.venv/bin/python -m ensurepip -q >/dev/null 2>&1 || true
.venv/bin/python -m pip install -q --upgrade pip
.venv/bin/python -m pip install -q pillow numpy
echo "Pillow $(.venv/bin/python -c 'import PIL; print(PIL.__version__)')"

say "2/5  This Mac's address on your wifi"
IP=""
for i in en0 en1 en2; do IP="$(ipconfig getifaddr "$i" 2>/dev/null || true)"; [ -n "$IP" ] && break; done
[ -n "$IP" ] || { echo "Couldn't find this Mac's wifi address. Is wifi on?"; exit 1; }
URL="http://$IP:8080/dash.png"
echo "$IP  ->  the Kindle will fetch $URL"
OLD="$(sed -n 's/^IMAGE_URLS*="\([^"]*\)".*/\1/p' "$KCFG")"     # earlier addresses stay as fallbacks
ALT=""; for u in $OLD; do
  [ "$u" = "$URL" ] && continue
  case " $ALT " in *" $u "*) ;; *) ALT="$ALT $u" ;; esac
done; ALT="${ALT# }"
sed -i '' "s|^IMAGE_URL=.*|IMAGE_URL=\"$URL\"|" "$KCFG"
if grep -q '^IMAGE_URLS=' "$KCFG"; then
  sed -i '' "s|^IMAGE_URLS=\"[^\"]*\"|IMAGE_URLS=\"$ALT\"|" "$KCFG"
else
  sed -i '' "/^IMAGE_URL=/a\\
IMAGE_URLS=\"$ALT\"   # also tried, in turn, if that address stops answering
" "$KCFG"
fi
grep '^IMAGE_URLS*=' "$KCFG"

say "3/5  First screen"
chmod +x local/*.sh
local/render_site.sh | tail -n 3
[ -s site/dash.png ] && [ -s site/version.txt ] || { echo "The first render failed - see above."; exit 1; }

say "4/5  Background jobs (render every 10 minutes, serve to the Kindle)"
mkdir -p "$AGENTS"
cat > "$AGENTS/local.kindleweather.render.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>local.kindleweather.render</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$ROOT/local/render_site.sh</string></array>
  <key>StartCalendarInterval</key><array>
    <dict><key>Minute</key><integer>4</integer></dict>
    <dict><key>Minute</key><integer>14</integer></dict>
    <dict><key>Minute</key><integer>24</integer></dict>
    <dict><key>Minute</key><integer>34</integer></dict>
    <dict><key>Minute</key><integer>44</integer></dict>
    <dict><key>Minute</key><integer>54</integer></dict>
  </array>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$ROOT/local/render.log</string>
  <key>StandardErrorPath</key><string>$ROOT/local/render.log</string>
</dict></plist>
PLIST
cat > "$AGENTS/local.kindleweather.serve.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>local.kindleweather.serve</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$ROOT/local/serve.sh</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/dev/null</string>
  <key>StandardErrorPath</key><string>/dev/null</string>
</dict></plist>
PLIST
for job in render serve; do
  launchctl bootout "gui/$UID_N/local.kindleweather.$job" >/dev/null 2>&1 || true
  launchctl bootstrap "gui/$UID_N" "$AGENTS/local.kindleweather.$job.plist"
done
sleep 3
if curl -fsS -m 5 "http://$IP:8080/version.txt" >/dev/null; then echo "Serving: open http://$IP:8080/ in a browser to see the screen."
else echo "The server isn't answering yet. If macOS asked whether Python may accept incoming connections, choose Allow, then run this again."; fi

say "5/5  The Kindle"
K=/Volumes/Kindle/extensions/weatherdash
if [ -d "$K" ]; then
  cp "$KCFG" "$K/config.sh" && echo "Pointed the Kindle at this Mac."
  echo "Now: eject the Kindle in Finder, unplug it, hold its power button ~40 s until the tree logo,"
  echo "then KUAL -> Weather dashboard -> Start dashboard."
else
  echo "The Kindle isn't connected as a drive, so it still points at GitHub."
  echo "Plug it in so 'Kindle' appears in Finder, then run:  bash $ROOT/local/install.sh"
fi
