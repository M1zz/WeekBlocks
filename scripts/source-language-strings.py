#!/usr/bin/env python3
# 원문(한국어) 표를 번들에 넣는다: <카탈로그> <나갈 .strings 경로>
#
# 왜 필요한가:
#   개발 언어를 영어로 둔다(→ WeekBlocks.project.yml developmentLanguage). 앱이 모르는 말
#   (독일어·프랑스어…)을 쓰는 사람에게 한국어 대신 영어가 뜨게 하려는 것이다.
#   그런데 카탈로그의 원문은 한국어라, xcstringstool 은 ko.lproj 에 Localizable.strings 를
#   만들지 않는다 (원문 언어는 '열쇠 = 글자'라서 표가 필요 없다고 본다).
#   표가 없으면 한국어를 고른 사람도 개발 언어(영어) 표로 넘어가 **영어가 뜬다.**
#   그래서 열쇠를 그대로 글자로 쓰는 한국어 표를 빌드마다 카탈로그에서 새로 만든다.
#   카탈로그에 한국어를 따로 적어 둔 문장(자리 순서를 바꾼 것 등)은 그 글자를 쓴다.
import json
import os
import plistlib
import sys

catalog_path, out_path = sys.argv[1], sys.argv[2]
with open(catalog_path, encoding="utf-8") as f:
    catalog = json.load(f)

source = catalog.get("sourceLanguage", "ko")
table = {}
for key, entry in catalog.get("strings", {}).items():
    if not key:
        continue
    unit = entry.get("localizations", {}).get(source, {}).get("stringUnit")
    table[key] = unit["value"] if unit and "value" in unit else key

os.makedirs(os.path.dirname(out_path), exist_ok=True)
# .strings 는 속성 목록 형식도 읽는다 — 따옴표·줄바꿈을 손으로 거를 일이 없다.
with open(out_path, "wb") as f:
    plistlib.dump(table, f, fmt=plistlib.FMT_BINARY)
print(f"{source}: {len(table)}개 → {out_path}")
