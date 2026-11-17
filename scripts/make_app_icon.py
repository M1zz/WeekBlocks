#!/usr/bin/env python3
"""무지개 공방 아이콘 — Icon Composer 유리 아이콘(WeekBlocks/AppIcon.icon)에서 평면 그림을 굽는다.

AppIcon.icon 은 아이폰 '욕망의 무지개'의 것과 같다 (그쪽 scripts/make_app_icon.py 가 층 PNG 를 그린다.
그림을 바꾸면 그쪽에서 다시 그려 AppIcon.icon 을 통째로 가져온다).
macOS 26 부터는 시스템이 AppIcon.icon 을 직접 그린다 — 라이트 · 다크가 저절로 갈린다.
여기서 굽는 것은 그보다 아래 macOS 가 쓰는 Assets.xcassets/AppIcon.appiconset 의 PNG 다 (라이트 한 벌).
"""
from pathlib import Path
import subprocess, tempfile
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ICON = ROOT / "WeekBlocks/AppIcon.icon"
SET = ROOT / "WeekBlocks/Assets.xcassets/AppIcon.appiconset"
ICTOOL = "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
S, BODY = 1024, 824   # 옛 macOS 아이콘 규격: 1024 칸 안에 824 몸통, 둘레는 비운다

f = Path(tempfile.mkdtemp()) / "i.png"
subprocess.run([ICTOOL, str(ICON), "--export-image", "--output-file", str(f), "--platform", "macOS",
                "--rendition", "Default", "--width", str(S), "--height", str(S), "--scale", "1"],
               check=True, stdout=subprocess.DEVNULL)
body = Image.open(f).convert("RGBA").resize((BODY, BODY), Image.LANCZOS)
master = Image.new("RGBA", (S, S), (0, 0, 0, 0))
master.alpha_composite(body, ((S - BODY) // 2, (S - BODY) // 2))
for size in (16, 32, 64, 128, 256, 512, 1024):
    master.resize((size, size), Image.LANCZOS).save(SET / f"{size}.png")
    print("wrote", size)
