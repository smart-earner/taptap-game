#!/bin/bash
set -euo pipefail

save_directory="${1:-${HOME}/Library/Application Support/SanguoTown-HeroTown09}"
engine_log="$save_directory/debug/engine-debug.jsonl"
godot_log="$save_directory/debug/godot-debug.jsonl"

if [[ ! -f "$engine_log" ]]; then
  echo "未找到经营引擎日志：$engine_log" >&2
  exit 1
fi

echo "经营引擎：$engine_log"
jq -s -r '
  map(select(.event == "world_state")) | last |
  "时间=\(.time) 周期=\(.cycle) 阶段=\(.phase) 夜间=\(.night) 任务=\(.activeTaskCount) 空闲=\(.idleAgentCount)\n" +
  "空闲原因：\n" + ([.agents[] | select(.status | startswith("task:") | not) | "  \(.id): \(.status) @ \(.node)"] | join("\n")) +
  "\n进行中工程：\n" + ([.projects[] | select(.completed == false) | "  \(.id): \(.completedWork)/\(.totalWork), phase=\(.phase), started=\(.stageStarted)"] | join("\n"))
' "$engine_log"

if [[ -f "$godot_log" ]]; then
  echo
  echo "Godot：$godot_log"
  jq -s -r 'map(select(.event == "request_error" or .level == "error")) | .[-10:][]? | "  \(.timestampUnixMs): \(.event) \(.error // .detail // "")"' "$godot_log"
fi
