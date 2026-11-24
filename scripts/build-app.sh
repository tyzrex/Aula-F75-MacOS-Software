#!/bin/zsh
# Builds dist/Keylume.app (and the `keylumectl` CLI next to it). Works with the Command Line Tools only.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product Keylume
swift build -c release --product keylumectl
BIN=$(swift build -c release --show-bin-path)
APP="dist/Keylume.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Keylume" "$APP/Contents/MacOS/Keylume"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp "$BIN/keylumectl" dist/keylumectl
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Keylume</string>
  <key>CFBundleDisplayName</key><string>Keylume</string>
  <key>CFBundleIdentifier</key><string>dev.sulav.keylume</string>
  <key>CFBundleExecutable</key><string>Keylume</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>0.2.0</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSInputMonitoringUsageDescription</key><string>Keylume talks to the keyboard's configuration interface (USB, 2.4G dongle or Bluetooth).</string>
</dict></plist>
PLIST
# A stable signing identity keeps the Input Monitoring permission across rebuilds (ad-hoc signatures change every build).
IDENTITY="AULA Hub Local Signing"
if security find-identity -p codesigning | grep -q "$IDENTITY"; then
  # The first attempt can fail with errSecInternalComponent while the keychain wakes up; retry.
  codesign --force --deep --sign "$IDENTITY" "$APP" 2>&1 | tail -1 || true
  codesign --verify "$APP" 2>/dev/null || { sleep 2; codesign --force --deep --sign "$IDENTITY" "$APP" 2>&1 | tail -1; }
else
  echo "note: no '$IDENTITY' certificate; using an ad-hoc signature (permissions must be re-granted after each build)"
  codesign --force --deep --sign - "$APP" 2>&1 | tail -1 || true
fi
echo "Built: $APP"
echo "CLI:   dist/keylumectl"
