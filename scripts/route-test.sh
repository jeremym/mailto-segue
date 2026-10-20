#!/usr/bin/env bash
#
# End-to-end dry run: launch "build/Mailto Segue.app" with a mailto: and a throwaway
# config, and print the plan it would have executed. Opens nothing.
#
#   scripts/route-test.sh [mailto-url] [fallback-destination-id]
set -euo pipefail
cd "$(dirname "$0")/.."

MAILTO="${1:-mailto:pat@acme.com,lee@acme.com?cc=cc@acme.com&subject=A%20%26%20B%20%3D%20C&body=line%20one%0Aline%20two}"
FALLBACK="${2:-gmail-work}"
APP="$(pwd)/build/Mailto Segue.app"
[[ -d "$APP" ]] || { echo "error: run make bundle first" >&2; exit 1; }

DIR="$(mktemp -d -t segue-route)"
PLAN="$DIR/plan.json"
cat > "$DIR/config.json" <<JSON
{
  "version": 1,
  "fallback": "$FALLBACK",
  "destinations": [
    { "id": "gmail-work", "name": "Gmail — work", "key": "1", "type": "webmail", "provider": "gmail",
      "account": { "email": "me@work.com" },
      "browser": { "bundleID": "com.google.Chrome", "profile": "Profile 1", "windowMode": "app" } },
    { "id": "yahoo-safari", "name": "Yahoo", "key": "2", "type": "webmail", "provider": "yahoo",
      "browser": { "bundleID": "com.apple.Safari" } },
    { "id": "firefox-work", "name": "Fastmail in Firefox", "key": "3", "type": "webmail", "provider": "fastmail",
      "browser": { "bundleID": "org.mozilla.firefox", "profile": "default-release", "container": "Work" } },
    { "id": "mail", "name": "Mail", "key": "4", "type": "app", "bundleID": "com.apple.mail" },
    { "id": "copy", "name": "Copy", "key": "5", "type": "clipboard", "copy": "all" },
    { "id": "chrome-handler", "name": "Chrome's own handler", "key": "6", "type": "browserHandler",
      "browser": { "bundleID": "com.google.Chrome", "profile": "Default" } }
  ]
}
JSON

# -a is essential: without it, open hands the mailto to the *default* mail app.
open -n -a "$APP" "$MAILTO" --args --support-dir "$DIR" --dry-run "$PLAN"
for ((t = 0; t < 300; t++)); do
    [[ -s "$PLAN" ]] && break
    sleep 0.01
done
if [[ -s "$PLAN" ]]; then
    cat "$PLAN"
else
    echo "error: no plan written within 3 s" >&2
    exit 1
fi
# The app should be gone shortly after.
sleep 0.5
if pgrep -x Segue >/dev/null; then
    echo "warning: Segue is still running after the hand-off" >&2
    exit 1
fi
echo "ok: Segue quit after the hand-off"
