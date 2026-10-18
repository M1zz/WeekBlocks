#!/bin/bash
#
# 배포 전 검사 — 실패하면 0이 아닌 값으로 끝나 아카이브를 막는다.
#
# 두 단계다: ① Release 로 짓는다 ② 단위 시험(WeekBlocksTests)을 돌린다.
#    UI 시험(WeekBlocksUITests)은 화면을 띄워 몇 분 걸리므로 여기서 돌리지 않는다 —
#    Xcode 에서 ⌘U 로, 또는 `-only-testing:WeekBlocksUITests` 로 따로 돌린다.
#
# Release 로 짓는 이유: Debug 만 통과하고 Release 에서 깨지는 일이 실제로 있다
# (#if DEBUG 안에만 있는 코드 — CloudSchemaPrimer 같은 것 — 를 밖에서 부르는 경우).
# 배포는 Release 로 나간다.
#
# 서명은 끈다. 여기서 보는 것은 컴파일이고, 서명·공증은 DeployBar 의 아카이브가 한다.
# 켜 두면 프로비저닝이 없는 기계에서 코드와 상관없이 떨어진다.
#
# 빌드 안에서 권한 문구 검사(scripts/check-permission-wording.sh, App Review 5.1.1(iv))도
# 함께 돈다 — 타겟의 preBuildScripts 라서 이 빌드가 통과하면 그것도 통과한 것이다.

set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT="WeekBlocks.xcodeproj"
SCHEME="WeekBlocks"

echo "🔍 배포 전 검사 — $SCHEME (Release, macOS)"

# 판정은 xcodebuild 의 종료 코드 하나로 한다. 로그를 grep 해서 판단하면
# 경고 문구에 "error:" 가 섞여 들어올 때 멀쩡한 빌드를 실패로 읽는다.
LOG="$(mktemp -t predeploy)"
if ! xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
     -configuration Release -destination 'generic/platform=macOS' \
     CODE_SIGNING_ALLOWED=NO \
     -quiet build > "$LOG" 2>&1; then
  echo "❌ Release 빌드 실패"
  tail -40 "$LOG"
  rm -f "$LOG"
  exit 1
fi
rm -f "$LOG"

echo "✅ Release 빌드 통과"

# 단위 시험 — 계약(LeeoPreflight)·핵심 로직. 숙주 앱은 메모리 안 스토어로만 뜬다
# (→ WeekBlocks/LaunchEnvironment.swift) — 이 맥의 진짜 데이터·iCloud 를 건드리지 않는다.
LOG="$(mktemp -t predeploy-test)"
if ! xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
     -destination 'platform=macOS' \
     CODE_SIGNING_ALLOWED=NO \
     -only-testing:WeekBlocksTests \
     -quiet test > "$LOG" 2>&1; then
  echo "❌ 단위 시험 실패"
  grep -E "error:|failed" "$LOG" | tail -40
  rm -f "$LOG"
  exit 1
fi
rm -f "$LOG"

echo "✅ 단위 시험 통과"
