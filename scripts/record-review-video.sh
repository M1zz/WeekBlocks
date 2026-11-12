#!/bin/zsh
# App Review 에 낼 화면 녹화를 만든다 — 앱을 켜는 것부터 보통 흐름, 요금제까지.
#   scripts/record-review-video.sh [출력.mp4]
#
# 이 맥의 화면 전체를 찍는다. 도는 동안(3분 남짓) 맥을 만지지 않는다.
# 전체 화면 Space 에 있으면 앱 창이 앞으로 못 나온다 — 일반 데스크톱에서 돌린다.
# 손은 WeekBlocksUITests/ReviewDemoUITests.swift, 답변문은 docs/APP_REVIEW_NOTES.md.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="${1:-$ROOT/docs/review/AppReview-macOS.mp4}"
WORK="$(mktemp -d -t review-video)"
DD="$WORK/dd"
BUNDLE=com.example.ScheduleDensityApp

echo "▸ 빌드"
xcodebuild -project WeekBlocks.xcodeproj -scheme WeekBlocks -destination 'platform=macOS' \
  -derivedDataPath "$DD" build-for-testing -quiet
APP="$(find "$DD/Build/Products/Debug" -maxdepth 1 -name '*.app' ! -name '*Runner*' | head -1)"

pkill -x WeekBlocks 2>/dev/null || true
sleep 1

echo "▸ 시험 손 대기"
TEST_RUNNER_REVIEW_DEMO=1 xcodebuild -project WeekBlocks.xcodeproj -scheme WeekBlocks \
  -destination 'platform=macOS' -derivedDataPath "$DD" test-without-building \
  -only-testing:WeekBlocksUITests/ReviewDemoUITests > "$WORK/test.log" 2>&1 &
XB=$!
for i in {1..240}; do grep -q "DEMO-READY" "$WORK/test.log" && break; sleep 0.5; done

echo "▸ 녹화 시작"
# ffmpeg(avfoundation)로 찍으면 UI 시험 중 시스템이 덮는 '자동화 실행 중' 막이 같이 찍힌다.
# screencapture 는 그 막을 빼고 찍는다. 커서와 클릭도 보인다(-C -k).
screencapture -v -C -k -x "$WORK/raw.mov" < /dev/null &
FF=$!
sleep 2

echo "▸ 앱 실행"
open -n "$APP" --args -uiTesting -usage.optOut YES \
  -AppleLanguages "(en)" -AppleLocale en_US -ApplePersistenceIgnoreState YES
sleep 2
# 이 맥OS 는 뒤에서 띄운 앱의 창을 바로 열지 않는다 — Dock 을 누른 것처럼 다시 열게 한다.
osascript -e "tell application id \"$BUNDLE\" to reopen" -e "tell application id \"$BUNDLE\" to activate"

wait $XB || true
sleep 1
kill -INT $FF; wait $FF 2>/dev/null || true
pkill -x WeekBlocks 2>/dev/null || true

grep -E "DEMO-MISSING|error:" "$WORK/test.log" || true
grep -q "DEMO-DONE" "$WORK/test.log" || { echo "✗ 손이 끝까지 못 갔다 — $WORK/test.log"; exit 1; }

echo "▸ 1080p 로 줄이기"
mkdir -p "$(dirname "$OUT")"
ffmpeg -hide_banner -loglevel error -y -i "$WORK/raw.mov" \
  -vf "scale=1920:-2,fps=30" -c:v libx264 -preset slow -crf 22 -pix_fmt yuv420p \
  -movflags +faststart "$OUT"
echo "✓ $OUT ($(du -h "$OUT" | cut -f1))"
