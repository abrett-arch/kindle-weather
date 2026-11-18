#!/bin/bash
# Serve ../site on port 8080 to the Kindle (and any browser) on the home network.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Each request is logged to serve.log, so you can see whether (and from where) the Kindle is checking in.
exec "$ROOT/.venv/bin/python" -m http.server 8080 --bind 0.0.0.0 --directory "$ROOT/site" 2>> "$ROOT/local/serve.log"
