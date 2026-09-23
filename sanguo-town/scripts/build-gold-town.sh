#!/bin/bash
# Independent local gameplay preview. Ad-hoc signed, not notarized distribution.
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
cmp spec/hero-town-v0.9.json Sources/SanguoLife/Resources/hero-town-v0.9.json
cmp spec/hero-town-v0.12-economy-delta.json Sources/SanguoLife/Resources/hero-town-v0.12-economy-delta.json
swift build --product SanguoMac
GAME_BIN="$(swift build --show-bin-path)"
GAME_APP="$PROJECT_ROOT/dist/SanguoTown-GoldTown.app"
mkdir -p "$GAME_APP/Contents/MacOS" "$GAME_APP/Contents/Resources/Life072" "$GAME_APP/Contents/Resources/HeroTown09" "$GAME_APP/Contents/Resources/HeroTown12"
cp "$GAME_BIN/SanguoMac" "$GAME_APP/Contents/MacOS/SanguoMac"
cp Sources/SanguoLife/Resources/catalog.json "$GAME_APP/Contents/Resources/Life072/catalog.json"
cp spec/hero-town-v0.9.json "$GAME_APP/Contents/Resources/HeroTown09/hero-town-v0.9.json"
cp spec/hero-town-v0.12-economy-delta.json "$GAME_APP/Contents/Resources/HeroTown12/hero-town-v0.12-economy-delta.json"
cp scripts/GoldTown-Info.plist "$GAME_APP/Contents/Info.plist"
codesign --force --sign - "$GAME_APP"
"$GAME_APP/Contents/MacOS/SanguoMac" --life-catalog-check
echo "$GAME_APP"
