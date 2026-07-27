#!/bin/bash
# .app 번들을 조립한다. Xcode 없이 SPM 산출물만으로 만든다.
#   ./scripts/bundle.sh          → debug 빌드
#   ./scripts/bundle.sh release  → release 빌드
set -euo pipefail

APP_NAME="LikeLionBar"
BUNDLE_ID="com.ryujunyeong.likelionbar"
VERSION="0.1.0"
BUILD_NUMBER="1"
MIN_MACOS="14.0"

CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "▸ swift build (-c $CONFIG)"
swift build -c "$CONFIG"

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BIN="$BIN_DIR/$APP_NAME"
[ -f "$BIN" ] || { echo "✗ 실행 파일 없음: $BIN"; exit 1; }

APP="$ROOT/build/$APP_NAME.app"
echo "▸ 번들 조립 → $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

# 아이콘이 있으면 넣는다. 없으면 Finder와 알림에 빈 사각형이 뜬다.
ICON_LINE=""
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
    ICON_LINE="    <key>CFBundleIconFile</key>                <string>AppIcon</string>"
    echo "▸ 아이콘 포함"
else
    echo "▸ 아이콘 없음 (./scripts/make-icon.sh 로 만드세요)"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>       <string>ko</string>
    <key>CFBundleExecutable</key>              <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>              <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>                    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>             <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>             <string>APPL</string>
    <key>CFBundleShortVersionString</key>      <string>$VERSION</string>
    <key>CFBundleVersion</key>                 <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>          <string>$MIN_MACOS</string>
$ICON_LINE
    <!-- Dock 아이콘 없이 메뉴바에만 상주 -->
    <key>LSUIElement</key>                     <true/>
    <key>NSHumanReadableCopyright</key>        <string>© 2026 류준영</string>
</dict>
</plist>
PLIST

# ad-hoc 서명. 알림(UNUserNotificationCenter)과 로그인 항목(SMAppService)은
# 서명되지 않은 번들에서 동작하지 않으므로 로컬 개발 중에도 반드시 필요하다.
# 배포용 Developer ID 서명은 scripts/sign.sh 에서 따로 한다.
echo "▸ ad-hoc 서명"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --verbose=2 "$APP" 2>&1 | sed 's/^/  /'

echo "✓ 완료: $APP"
echo "  실행: open \"$APP\""
