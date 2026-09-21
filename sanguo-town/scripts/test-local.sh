#!/bin/bash
# Run the Swift test suite with either a full Xcode toolchain or Apple's
# standalone Command Line Tools. Some CLT releases ship Testing.framework
# without making it visible to SwiftPM, and omit the _Testing_Foundation
# cross-import module. Keep that host-only workaround out of Package.swift so
# CI and full Xcode builds retain their normal configuration.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MODE="${1:-debug}"
case "$MODE" in
  debug|release|all) ;;
  *)
    echo "Usage: $0 [debug|release|all]" >&2
    exit 2
    ;;
esac

SWIFT_TEST_COMPAT=()
if ! swift -e 'import Testing' >/dev/null 2>&1; then
  DEVELOPER_ROOT="$(xcode-select -p)"
  TESTING_FRAMEWORKS="$DEVELOPER_ROOT/Library/Developer/Frameworks"
  if [[ ! -d "$TESTING_FRAMEWORKS/Testing.framework" ]]; then
    echo "Testing.framework is unavailable. Install a current Xcode or Command Line Tools release." >&2
    exit 1
  fi

  SWIFT_TEST_COMPAT=(
    -Xswiftc -F
    -Xswiftc "$TESTING_FRAMEWORKS"
    -Xswiftc -Xfrontend
    -Xswiftc -disable-cross-import-overlays
    -Xlinker -F
    -Xlinker "$TESTING_FRAMEWORKS"
    -Xlinker -rpath
    -Xlinker "$TESTING_FRAMEWORKS"
  )
  echo "Using Command Line Tools compatibility flags for Testing.framework."
fi

run_tests() {
  local configuration="$1"
  if [[ "$configuration" == "release" ]]; then
    swift test -c release "${SWIFT_TEST_COMPAT[@]}"
  else
    swift test "${SWIFT_TEST_COMPAT[@]}"
  fi
}

if [[ "$MODE" == "all" ]]; then
  run_tests debug
  run_tests release
else
  run_tests "$MODE"
fi
