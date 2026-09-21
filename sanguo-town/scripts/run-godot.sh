#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-$PROJECT_ROOT/../.tools/godot/Godot.app/Contents/MacOS/Godot}"
if [[ ! -x "$GODOT_BIN" ]]; then
  echo "Godot 尚未安装到项目 .tools/godot；也可以通过 GODOT_BIN 指定官方 Godot 可执行文件。" >&2
  exit 1
fi
cd "$PROJECT_ROOT"
bash scripts/build-godot-desktop.sh
swift build -c release --product SanguoLifeCLI
BRIDGE_BIN="$(swift build -c release --show-bin-path)"
mkdir -p godot/bin
cp "$BRIDGE_BIN/SanguoLifeCLI" godot/bin/
cp -R "$BRIDGE_BIN/SanguoTown_SanguoLife.bundle" godot/bin/
"$GODOT_BIN" --path "$PROJECT_ROOT/godot" --headless --editor --import --quit
exec "$GODOT_BIN" --path "$PROJECT_ROOT/godot" "$@"
