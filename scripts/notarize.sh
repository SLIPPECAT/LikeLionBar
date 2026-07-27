#!/bin/bash
# Apple 공증을 받고 티켓을 앱에 붙인다. 이걸 해야 동기들이 경고 없이 열 수 있다.
#
# 최초 1회 자격증명 저장:
#   xcrun notarytool store-credentials likelionbar \
#       --apple-id <애플 계정> --team-id <팀 ID> --password <앱 암호>
#
#   앱 암호는 appleid.apple.com → 로그인 및 보안 → 앱 암호 에서 만듭니다.
#   (계정 비밀번호가 아닙니다)
#
#   ./scripts/notarize.sh
set -euo pipefail

APP_NAME="LikeLionBar"
PROFILE="${NOTARY_PROFILE:-likelionbar}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/$APP_NAME.app"
ZIP="$ROOT/build/$APP_NAME.zip"
[ -d "$APP" ] || { echo "✗ 먼저 ./scripts/sign.sh 를 실행하세요"; exit 1; }

# grep -q 를 파이프라인에 쓰면 안 된다. 매치 즉시 종료하면서 codesign이 SIGPIPE로 죽고,
# pipefail이 그걸 실패로 잡아 매치에 성공했는데도 가드가 발동한다.
AUTHORITY="$(codesign -dv --verbose=2 "$APP" 2>&1 | grep '^Authority=' || true)"
case "$AUTHORITY" in
    *"Developer ID Application"*) ;;
    *)
        echo "✗ Developer ID로 서명되지 않았습니다. ./scripts/sign.sh 를 먼저 실행하세요."
        exit 1
        ;;
esac

echo "▸ 압축"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "▸ 공증 제출 (몇 분 걸립니다)"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

echo "▸ 티켓 첨부"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

# 티켓은 .app 안에 붙으므로 붙인 뒤 다시 압축해야 배포본에 포함된다.
echo "▸ 배포본 재압축"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "▸ Gatekeeper 최종 판정"
spctl -a -vvv -t exec "$APP" 2>&1 | sed 's/^/  /'

echo "✓ 완료 — 이 파일을 나눠주세요: $ZIP"
