#!/usr/bin/env bash
# Runs the Swift Testing suite. Extra arguments are passed to `swift test`.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXTRA=()

# With only the Command Line Tools installed (no Xcode), SwiftPM neither links the
# test bundle with an rpath to Testing.framework / lib_TestingInterop.dylib nor
# reliably finds the TestingMacros plugin on incremental rebuilds. Point it at
# the CLT copies explicitly. Not needed (and skipped) with a full Xcode.
DEV_DIR="$(xcode-select -p 2>/dev/null || true)"
if [[ "$DEV_DIR" == */CommandLineTools ]]; then
    EXTRA+=(
        -Xswiftc -plugin-path -Xswiftc "$DEV_DIR/usr/lib/swift/host/plugins/testing"
        -Xlinker -rpath -Xlinker "$DEV_DIR/Library/Developer/Frameworks"
        -Xlinker -rpath -Xlinker "$DEV_DIR/Library/Developer/usr/lib"
    )
fi

swift test --package-path "$ROOT" ${EXTRA[@]+"${EXTRA[@]}"} "$@"
