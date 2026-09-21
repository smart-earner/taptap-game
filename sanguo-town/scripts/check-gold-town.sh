#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
cmp spec/hero-town-v0.9.json Sources/SanguoLife/Resources/hero-town-v0.9.json
swift run SanguoLifeCLI --gacha-check
swift run SanguoLifeCLI --hero-town-v09-check
swift run SanguoLifeCLI --hero-check
python3 scripts/validate_hero_town_v09.py
