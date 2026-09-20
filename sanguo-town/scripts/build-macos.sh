#!/bin/bash
# Local development bundle only; not a notarized distribution build.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == "Darwin" ]] || { echo "Requires macOS and Xcode/Swift 6 toolchain." >&2; exit 1; }
[[ "$(uname -m)" == "arm64" ]] || { echo "This development bundle targets Apple Silicon." >&2; exit 1; }
swift build -c release --product SanguoMac --arch arm64
BIN="$(swift build -c release --show-bin-path --arch arm64)"
APP="$ROOT/dist/SanguoTown-Development.app"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN/SanguoMac" "$APP/Contents/MacOS/SanguoMac"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SanguoMac</string>
<key>CFBundleIdentifier</key><string>dev.sanguotown.prototype</string>
<key>CFBundleName</key><string>小城志开发版</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Built local ad-hoc development bundle: $APP"
echo "Not notarized. Do not distribute as a signed release. No security settings need to be disabled."
