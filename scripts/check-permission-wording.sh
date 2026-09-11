#!/bin/bash
#
# **권한 창 앞에 '허용'을 세우지 않는다.**
#
# 1.1.3(15)이 App Review 5.1.1(iv)로 돌아왔다 (2026-09-10). 설정의 캘린더 단추가
# "캘린더 접근 허용 / Allow calendar access"였고, 누르면 곧바로 시스템 권한 창이 떴다.
# 앱 안의 단추가 '허용'이면 사람은 이미 허락한 셈이 되어 시스템 창에서도 허용 쪽으로
# 떠밀린다 — 애플은 이걸 '권한을 주도록 이끈다'로 읽는다. 쓸 수 있는 말은 '계속'·'다음'뿐이다.
#
# 이 검사는 빌드마다 돈다. 소스의 문자열과 문자열 카탈로그(한·영)를 훑어서
# 허용·허락 / Allow·Grant·Authorize 가 사람에게 보이는 문장에 들어 있으면 빌드를 멈춘다.
#
# ⚠️ 권한과 상관없는 자리에서 꼭 써야 하면, 그 줄 끝에 `// permission-wording: ok` 를 붙인다.
#    문자열 카탈로그에는 주석을 달 수 없으니 소스 쪽 줄에 붙이고, 카탈로그의 영어 번역은
#    다른 말로 옮긴다. 권한 창 앞 단추라면 예외를 달지 말고 낱말을 바꾼다.
#
set -euo pipefail

ROOT="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT"

files=()
for f in WeekBlocks/*.swift TodoShare/*.swift \
         WeekBlocks/*.xcstrings TodoShare/*.xcstrings; do
    [ -f "$f" ] && files+=("$f")
done

awk '
    /^[[:space:]]*\/\//            { next }   # 주석 줄
    /permission-wording: ok/       { next }   # 예외를 단 줄
    {
        line = $0
        while (match(line, /"[^"]*"/)) {
            lit = substr(line, RSTART, RLENGTH)
            line = substr(line, RSTART + RLENGTH)
            if (lit ~ /허용|허락/ || tolower(lit) ~ /(^|[^a-z])(allow|grant|authori[sz]e)([^a-z]|$)/) {
                printf "%s:%d: error: 권한 창 앞에 허용/Allow 류 낱말을 쓰지 않습니다 (App Review 5.1.1(iv)). \"계속/Continue\"를 쓰세요 → %s\n", FILENAME, FNR, lit
                found = 1
            }
        }
    }
    END { exit found }
' "${files[@]}"
