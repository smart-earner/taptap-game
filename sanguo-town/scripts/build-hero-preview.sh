#!/bin/bash
# Independent local, ad-hoc signed preview; no migration of existing saves.
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
swift build --product SanguoMac
PREVIEW_BIN="$(swift build --show-bin-path)"
PREVIEW_APP="$PROJECT_ROOT/dist/SanguoTown-HeroPreview.app"
mkdir -p "$PREVIEW_APP/Contents/MacOS" "$PREVIEW_APP/Contents/Resources/Life072"
cp "$PREVIEW_BIN/SanguoMac" "$PREVIEW_APP/Contents/MacOS/SanguoMac"
cp Sources/SanguoLife/Resources/catalog.json "$PREVIEW_APP/Contents/Resources/Life072/catalog.json"
cp scripts/HeroPreview-Info.plist "$PREVIEW_APP/Contents/Info.plist"
codesign --force --sign - "$PREVIEW_APP"
"$PREVIEW_APP/Contents/MacOS/SanguoMac" --life-catalog-check
echo "$PREVIEW_APP"
