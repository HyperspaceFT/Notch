#!/usr/bin/env bash
# Quits any running Notch and launches build/Notch.app. Extra arguments are passed
# to the app, e.g. scripts/run.sh -NotchDebugState expanded
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Notch.app"

if [[ ! -d "$APP" ]]; then
    echo "error: $APP not found; run scripts/build-app.sh first" >&2
    exit 1
fi

pkill -x Notch || true
# Give the old instance a moment to exit so `open` does not just re-focus it.
for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -x Notch >/dev/null || break
    sleep 0.2
done

if [[ $# -gt 0 ]]; then
    open "$APP" --args "$@"
else
    open "$APP"
fi
