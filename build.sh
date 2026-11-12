#!/bin/bash
# Builds PluginUnlocker.app from PluginUnlocker.swift.
# Needs the Xcode Command Line Tools (xcode-select --install). No Xcode project required.
set -e
cd "$(dirname "$0")"

APP="PluginUnlocker"
OUT="$APP.app"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS"

echo "Compilando…"
swiftc -O -framework AppKit -o "$OUT/Contents/MacOS/$APP" PluginUnlocker.swift

cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>                 <string>$APP</string>
  <key>CFBundleDisplayName</key>          <string>Plugin Unlocker</string>
  <key>CFBundleIdentifier</key>           <string>local.pluginunlocker</string>
  <key>CFBundleVersion</key>              <string>1.0</string>
  <key>CFBundleShortVersionString</key>   <string>1.0</string>
  <key>CFBundleExecutable</key>           <string>$APP</string>
  <key>CFBundlePackageType</key>          <string>APPL</string>
  <key>LSMinimumSystemVersion</key>       <string>11.0</string>
  <key>LSUIElement</key>                  <true/>
</dict>
</plist>
PLIST

# Ad-hoc sign the app itself so it runs cleanly.
codesign --force --deep --sign - "$OUT"

echo "Listo: $(pwd)/$OUT"
echo "Para instalarla:  mv \"$OUT\" /Applications/"
