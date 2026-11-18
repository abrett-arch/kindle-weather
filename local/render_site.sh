#!/bin/bash
# Make the dashboard screen and publish it to ../site, where serve.sh hands it to the Kindle.
# Run by launchd at 4, 14, 24, 34, 44 and 54 minutes past each hour (just after BOM's readings).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
SITE="$ROOT/site"; WORK="$ROOT/.build"; PY="$ROOT/.venv/bin/python"
LOG="$ROOT/local/render.log"
[ -t 1 ] || exec >> "$LOG" 2>&1
echo "== $(date '+%Y-%m-%d %H:%M:%S')"
rm -rf "$WORK"; mkdir -p "$WORK/site" "$SITE"
args=()
[ -s "$SITE/state.json" ] && args+=(--prev "$SITE/state.json")
[ -s "$SITE/dash.png" ] && args+=(--prev-image "$SITE/dash.png")
# shellcheck disable=SC2086
"$PY" render.py --out "$WORK/site/dash.png" ${RENDER_ARGS:-} ${args[@]+"${args[@]}"} || { echo "render failed"; exit 1; }
cp web/* "$WORK/site/"
# the Kindle's own code, for its over-the-air updates (same layout as the old GitHub site)
"$PY" - "$ROOT/kindle/extensions/weatherdash" "$WORK/site/kindle" <<'PY'
import hashlib, shutil, sys
from pathlib import Path
src, dst = Path(sys.argv[1]), Path(sys.argv[2])
lines = []
for f in sorted((p for p in src.rglob("*") if p.is_file() and p.suffix != ".log"
                 and not p.name.startswith("._") and p.name != ".DS_Store"),
                key=lambda p: p.relative_to(src).as_posix().encode()):
    rel = f.relative_to(src).as_posix()
    (dst / rel).parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(f, dst / rel)
    lines.append(f"{hashlib.md5(f.read_bytes()).hexdigest()} {rel}\n")
files = "".join(lines)
version = hashlib.md5(files.encode()).hexdigest()[:12]
(dst / "manifest.txt").write_text(f"version {version}\n" + files)
print("kindle code version", version)
PY
cat > "$WORK/site/index.html" <<'HTML'
<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>Hobart weather dashboard</title><meta http-equiv="refresh" content="300">
<body style="margin:0;background:#888;display:grid;place-items:center;min-height:100vh">
<img src="preview.png" style="max-width:100%;max-height:100vh" alt="Hobart weather">
HTML
# publish: everything else first, version.txt last (it tells the Kindle a new screen is ready)
"$PY" - "$WORK/site" "$SITE" <<'PY'
import os, shutil, sys
from pathlib import Path
src, dst = Path(sys.argv[1]), Path(sys.argv[2])
new = {p.relative_to(src) for p in src.rglob("*") if p.is_file()}
for rel in sorted(new, key=lambda r: (r.name == "version.txt", str(r))):    # version.txt last
    (dst / rel).parent.mkdir(parents=True, exist_ok=True)
    tmp = dst / rel.parent / (".tmp-" + rel.name)
    shutil.copyfile(src / rel, tmp); os.replace(tmp, dst / rel)
for p in dst.rglob("*"):                                                   # drop leftovers
    if p.is_file() and p.relative_to(dst) not in new:
        p.unlink()
PY
echo "published $(cat "$SITE/version.txt")"
# keep the logs short (serve.log: one line per request from the Kindle)
SLOG="$ROOT/local/serve.log"
if [ -f "$SLOG" ] && [ "$(wc -l < "$SLOG")" -gt 20000 ]; then tail -n 5000 "$SLOG" > "$SLOG.tmp" && cat "$SLOG.tmp" > "$SLOG" && rm -f "$SLOG.tmp"; fi
if [ -f "$LOG" ] && [ "$(wc -l < "$LOG")" -gt 3000 ]; then tail -n 1500 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"; fi
