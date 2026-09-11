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

echo "==> Compiling icon"
# Assets.car holds the light/dark/tinted variants; AppIcon.icns is the fallback for older macOS.
if xcrun actool Resources/AppIcon.icon --compile "$APP/Contents/Resources" \
    --app-icon AppIcon --platform macosx --target-device mac --minimum-deployment-target 15.0 \
    --output-partial-info-plist build/icon-partial.plist >/dev/null; then
  echo "    icon embedded"
else
  echo "    icon skipped (actool failed; .icon needs Xcode 26+)"
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
