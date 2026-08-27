#!/bin/bash
# Builds Defaulter.app. Pass --install to copy it into /Applications.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${CONFIG:-release}"
APP="build/Defaulter.app"

echo "==> Compiling ($CONFIG)"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Defaulter"

echo "==> Assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Defaulter"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Generating icon"
if swift makeicon.swift >/dev/null 2>&1 && [ -d build/AppIcon.iconset ]; then
  iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null \
    && echo "    icon embedded" || echo "    icon skipped (iconutil failed)"
  rm -rf build/AppIcon.iconset
else
  echo "    icon skipped (generator failed)"
fi

echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - "$APP" 2>/dev/null && echo "    signed" || echo "    unsigned"

# Nudge Launch Services so the new bundle is registered immediately.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$APP" >/dev/null 2>&1 || true

echo "==> Built $APP"

if [ "${1:-}" = "--install" ]; then
  echo "==> Installing to /Applications"
  rm -rf "/Applications/Defaulter.app"
  cp -R "$APP" "/Applications/Defaulter.app"
  echo "==> Installed. Open with: open -a Defaulter"
fi
