#!/bin/bash
set -euo pipefail
GAME_PROJECT="$(cd "$(dirname "$0")" && pwd)"
bash "$GAME_PROJECT/scripts/run-godot.sh"
