#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$PROJECT_ROOT/godot/bin"
clang -dynamiclib -fobjc-arc -O2 -Wall -Wextra -Wno-unused-parameter -Wno-cast-function-type-mismatch \
  -framework AppKit -framework CoreGraphics \
  "$PROJECT_ROOT/godot/native/desktop_host.m" \
  -o "$PROJECT_ROOT/godot/bin/libtown_desktop.dylib"
