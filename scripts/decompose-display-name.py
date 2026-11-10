#!/usr/bin/env python3
# 만든 앱의 Info.plist 에서 CFBundleDisplayName 을 풀어쓴 한글(NFD)로 바꾼다: <Info.plist 경로>
#
# 왜 필요한가:
#   독·파인더·런치패드는 LSHasLocalizedDisplayName 이 켜져 있어도, **디스크의 폴더 이름이
#   CFBundleDisplayName 과 바이트까지 같을 때만** lproj 의 이름('Rainbow Craft')을 쓴다.
#   다르면 "사람이 이름을 바꿨다"고 보고 폴더 이름을 그대로 보여 준다.
#   그런데 앱스토어(그리고 ditto·pkg)는 한글 폴더 이름을 자모로 풀어서(NFD) 깐다.
#   Info.plist 의 '무지개 공방'은 모아쓴 글자(NFC)라 눈에는 같아도 바이트가 달라,
#   영어를 쓰는 사람의 독에도 '무지개 공방'이 떴다 (2026-11-10 사용자 제보로 확인).
#   그래서 깔린 뒤의 폴더 이름과 같아지도록 이 값만 NFD 로 적는다.
#
#   ⚠️ Xcode 가 만든 그대로의 앱(폴더 이름 NFC)은 거꾸로 폴더 이름이 보인다 — 개발 맥에서만
#      그렇고, 스토어로 깔린 앱은 맞다. 확인은 /Applications 에 깔린 것으로 할 것.
#   ⚠️ CFBundleName 은 건드리지 않는다 (메뉴 막대·스포트라이트가 쓴다. 비교에는 안 쓰인다).
import plistlib
import sys
import unicodedata

path = sys.argv[1]
with open(path, "rb") as f:
    head = f.read(8)
    f.seek(0)
    info = plistlib.load(f)

name = info.get("CFBundleDisplayName")
if not name:
    sys.exit("error: CFBundleDisplayName 이 없다 — 독에 뜨는 이름을 맞출 수 없다: " + path)

decomposed = unicodedata.normalize("NFD", name)
if decomposed != name:
    info["CFBundleDisplayName"] = decomposed
    fmt = plistlib.FMT_BINARY if head.startswith(b"bplist") else plistlib.FMT_XML
    with open(path, "wb") as f:
        plistlib.dump(info, f, fmt=fmt)
