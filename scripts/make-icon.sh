#!/bin/bash
# PNG 한 장으로 앱 아이콘(.icns)을 만든다.
#
#   ./scripts/make-icon.sh ~/Downloads/lion.png
#
# 1024x1024 정사각형 PNG를 넣으세요. 배경이 투명하면 그대로 살아납니다.
set -euo pipefail

SRC="${1:-}"
[ -n "$SRC" ] || { echo "사용법: ./scripts/make-icon.sh <1024x1024 PNG>"; exit 1; }
[ -f "$SRC" ] || { echo "✗ 파일을 찾을 수 없습니다: $SRC"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICONSET="$ROOT/build/AppIcon.iconset"
OUT="$ROOT/Resources/AppIcon.icns"

W=$(sips -g pixelWidth "$SRC" | awk '/pixelWidth/{print $2}')
H=$(sips -g pixelHeight "$SRC" | awk '/pixelHeight/{print $2}')
echo "▸ 원본 ${W}x${H}"
[ "$W" = "$H" ] || echo "  ⚠️  정사각형이 아닙니다. 찌그러질 수 있습니다."
[ "$W" -ge 1024 ] || echo "  ⚠️  1024px보다 작아 큰 크기에서 흐려집니다."

rm -rf "$ICONSET"
mkdir -p "$ICONSET" "$ROOT/Resources"

for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" "$SRC" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
    RETINA=$((SIZE * 2))
    sips -z "$RETINA" "$RETINA" "$SRC" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$OUT"
rm -rf "$ICONSET"

echo "✓ 만들어짐: $OUT"
echo "  이제 ./scripts/bundle.sh 를 실행하면 앱에 반영됩니다."
