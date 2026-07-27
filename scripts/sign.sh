#!/bin/bash
# 배포용 Developer ID 서명.
#
#   ./scripts/sign.sh
#   DEVELOPER_ID="Developer ID Application: 이름 (TEAMID)" ./scripts/sign.sh
#
# 공증(notarize)을 받으려면 hardened runtime(--options runtime)이 필수다.
set -euo pipefail

APP_NAME="LikeLionBar"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/$APP_NAME.app"
[ -d "$APP" ] || { echo "✗ 먼저 ./scripts/bundle.sh release 를 실행하세요"; exit 1; }

IDENTITY="${DEVELOPER_ID:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)".*/\1/')
fi

if [ -z "$IDENTITY" ]; then
    cat <<'MSG'
✗ Developer ID Application 인증서를 찾을 수 없습니다.

  1. developer.apple.com → Certificates, Identifiers & Profiles
  2. Certificates → + → "Developer ID Application" 선택
  3. 키체인 접근 → 인증서 지원 → 인증 기관에서 인증서 요청… 으로 CSR을 만들어 업로드
  4. 내려받은 .cer 파일을 더블클릭해 키체인에 설치
  5. 확인:  security find-identity -v -p codesigning
MSG
    exit 1
fi

echo "▸ 서명 주체: $IDENTITY"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"

echo "▸ 검증"
codesign --verify --strict --verbose=2 "$APP" 2>&1 | sed 's/^/  /'

echo "▸ Gatekeeper 판정 (공증 전이라 거부되는 게 정상)"
spctl -a -vvv -t exec "$APP" 2>&1 | sed 's/^/  /' || true

echo "✓ 서명 완료 — 다음: ./scripts/notarize.sh"
