#!/bin/bash
# .app 번들을 조립한다. Xcode 없이 SPM 산출물만으로 만든다.
#   ./scripts/bundle.sh          → debug 빌드
#   ./scripts/bundle.sh release  → release 빌드
set -euo pipefail

APP_NAME="LikeLionBar"
BUNDLE_ID="com.ryujunyeong.likelionbar"
VERSION="0.2.0"
BUILD_NUMBER="2"
MIN_MACOS="14.0"

CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP="$ROOT/build/$APP_NAME.app"
DEST="$APP/Contents/MacOS/$APP_NAME"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# 빌드 로그는 stderr로 흘리고 stdout에는 실행 파일 경로만 남긴다.
build_for() {
    local triple="$1"
    swift build -c "$CONFIG" --triple "$triple" >&2
    echo "$(swift build -c "$CONFIG" --triple "$triple" --show-bin-path)/$APP_NAME"
}

if [ "$CONFIG" = "release" ]; then
    # 배포본은 Intel 맥에서도 열려야 한다. Rosetta는 x86을 ARM으로 번역하는 것이라
    # 반대 방향은 못 도와주므로, arm64 전용으로 내보내면 Intel 맥에서는 실행이 안 된다.
    # --arch 다중 지정은 Xcode의 xcbuild를 요구하므로, 따로 빌드해 lipo로 합친다.
    echo "▸ swift build (release, arm64)"
    ARM_BIN="$(build_for "arm64-apple-macosx$MIN_MACOS")"
    echo "▸ swift build (release, x86_64)"
    X86_BIN="$(build_for "x86_64-apple-macosx$MIN_MACOS")"
    echo "▸ lipo로 유니버설 생성"
    lipo -create "$ARM_BIN" "$X86_BIN" -output "$DEST"
else
    echo "▸ swift build (-c $CONFIG)"
    swift build -c "$CONFIG"
    cp "$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME" "$DEST"
fi

[ -f "$DEST" ] || { echo "✗ 실행 파일 생성 실패"; exit 1; }
echo "▸ 번들 조립 → $APP"

# 메뉴바에 띄울 사자 표정들.
if [ -d "$ROOT/Resources/faces" ]; then
    cp "$ROOT"/Resources/faces/*.png "$APP/Contents/Resources/" 2>/dev/null
    echo "▸ 표정 $(ls "$ROOT/Resources/faces"/*.png 2>/dev/null | wc -l | tr -d ' ')개 포함"
fi

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

echo "✓ 완료: $APP  ($(lipo -archs "$APP/Contents/MacOS/$APP_NAME"))"
echo "  실행: open \"$APP\""
