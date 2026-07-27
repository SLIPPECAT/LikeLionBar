#!/bin/bash
# 임의 시각의 메뉴바 상태를 즉시 미리본다. 다음날 아침을 기다리지 않기 위한 도구.
#
#   ./scripts/preview.sh 08:47:00              → 23:00 카운트다운
#   ./scripts/preview.sh 09:04:30              → 30초 뒤 깜빡임으로 전환
#   ./scripts/preview.sh 09:11:00              → 지각
#   ./scripts/preview.sh 09:30:00 checkIn      → 강의실 입장 조르기
#   ./scripts/preview.sh 17:58:00 checkIn,classroom → 퇴실
#
# 3번째 인자는 배속. 알림 4번을 실시간으로 보려면 21분이 걸리므로 압축해서 본다.
#   ./scripts/preview.sh 08:46:30 "" 30   → 실시간 1초가 가짜 30초
set -euo pipefail

TIME="${1:-08:47:00}"
DONE="${2:-}"
SPEED="${3:-1}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/LikeLionBar.app"
[ -d "$APP" ] || { echo "✗ 먼저 ./scripts/bundle.sh 를 실행하세요"; exit 1; }

DAY="$(date +%Y-%m-%d)"
WEEKDAY="$(date +%u)"   # 1=월 … 7=일
if [ "$WEEKDAY" -ge 6 ]; then
    # 주말에는 엔진이 조용히 있으므로 미리보기가 안 된다. 가장 가까운 월요일로 옮긴다.
    DAY="$(date -v+$((8 - WEEKDAY))d +%Y-%m-%d)"
    echo "· 오늘은 주말이라 미리보기 날짜를 $DAY (월요일)로 옮깁니다"
fi

pkill -f "LikeLionBar.app/Contents/MacOS/LikeLionBar" 2>/dev/null || true
sleep 0.3

echo "▸ 가짜 시각 ${DAY}T${TIME}${DONE:+  (완료: $DONE)}$([ "$SPEED" != "1" ] && echo "  ${SPEED}배속")"
# 실행 파일을 직접 돌리면 LaunchServices에 앱으로 등록되지 않아 알림 권한이 통하지 않는다.
# 반드시 번들을 open으로 띄운다.
open -n "$APP" --env "LIKELIONBAR_FAKE_TIME=${DAY}T${TIME}" \
    --env "LIKELIONBAR_FAKE_DONE=$DONE" --env "LIKELIONBAR_FAKE_SPEED=$SPEED"

sleep 1.5
if pgrep -f "LikeLionBar.app/Contents/MacOS/LikeLionBar" >/dev/null; then
    echo "✓ 실행 중 — 메뉴바를 확인하세요"
else
    echo "✗ 실행 실패"
    exit 1
fi
