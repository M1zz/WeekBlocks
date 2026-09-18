#!/bin/bash
#
# 배포 전 검사 — 실패하면 0이 아닌 값으로 끝나 아카이브를 막는다.
#
# ⚠️ **이 앱에는 테스트 타겟이 없다.** 그래서 이 검사가 지킬 수 있는 것은
#    "적어도 컴파일은 된다"까지다. 초록불이 떠도 동작이 옳다는 뜻이 아니다.
#    테스트 타겟이 생기면 아래 build 를 test 로 바꾸고 -only-testing 을 붙인다.
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

echo "✅ Release 빌드 통과 (⚠️ 테스트 타겟이 없어 컴파일만 확인했습니다)"
