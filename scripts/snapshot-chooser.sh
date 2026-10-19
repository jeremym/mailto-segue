#!/usr/bin/env bash
#
# Render the chooser to PNGs (one per layout) without a screen recording
# permission. Uses a throwaway config with six destinations.
#
#   scripts/snapshot-chooser.sh [out-dir]   (default .context/snapshots)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-.context/snapshots}"
mkdir -p "$OUT"
APP="$(pwd)/build/Segue.app"
[[ -d "$APP" ]] || { echo "error: run make bundle first" >&2; exit 1; }

for layout in largeTiles smallTiles compactList; do
    DIR="$(mktemp -d -t segue-snap)"
    cat > "$DIR/config.json" <<JSON
{ "chooser": { "layout": "$layout" },
  "destinations": [
    { "id": "gmail-personal", "name": "Gmail — personal", "key": "1", "type": "webmail", "provider": "gmail",
      "account": { "email": "jeremy@example.com" }, "browser": { "bundleID": "com.google.Chrome", "profile": "Default", "profileName": "Your Chrome" },
      "sendsAs": ["jeremy@example.com"] },
    { "id": "gmail-work", "name": "Gmail — work", "key": "2", "type": "webmail", "provider": "gmail",
      "account": { "email": "me@work.example" }, "browser": { "bundleID": "com.brave.Browser", "profile": "Default" },
      "sendsAs": ["me@work.example"], "color": "#1A73E8", "pinned": true },
    { "id": "proton", "name": "Proton", "key": "3", "type": "webmail", "provider": "proton",
      "browser": { "bundleID": "org.mozilla.firefox" }, "sendsAs": ["me@proton.example"] },
    { "id": "mail", "name": "Mail", "key": "4", "type": "app", "bundleID": "com.apple.mail" },
    { "id": "copy", "name": "Copy address", "key": "c", "type": "clipboard", "copy": "addresses" },
    { "id": "handler", "name": "Chrome's handler", "key": "5", "type": "browserHandler", "browser": { "bundleID": "com.google.Chrome" } }
  ] }
JSON
    PNG="$(pwd)/$OUT/chooser-$layout.png"
    rm -f "$PNG"
    open -n -a "$APP" "mailto:pat@acme.com?subject=Q3%20numbers%20%26%20plans" --args --support-dir "$DIR" --dry-run "$DIR/plan.json" --snapshot "$PNG"
    for ((t = 0; t < 300; t++)); do [[ -s "$PNG" ]] && break; sleep 0.01; done
    [[ -s "$PNG" ]] && echo "wrote $PNG" || echo "error: no snapshot for $layout" >&2
done
