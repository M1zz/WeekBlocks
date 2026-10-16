#!/usr/bin/env python3
"""인앱 구입 홍보 이미지 (1024×1024) — 월간 · 연간 · 평생.

App Store Connect ▸ 인앱 구입 ▸ 상품 ▸ '홍보 이미지' 칸에 올린다.
제품 페이지에 상품을 띄우거나 윈백 제안을 낼 때 쓰인다.

글자를 넣지 않는다 — 상품 이름은 스토어가 옆에 따로 적으므로, 글이 없으면 한 벌로
23개 언어에 다 쓴다. 가격·할인도 넣지 않는다 (Apple 가이드).

그림은 앱 아이콘의 말을 이어 쓴다: 어두운 보랏빛 바탕 위의 둥근 무지개 블록.
  월간  한 달 달력 — 하루가 블록 하나
  연간  열두 달 막대 — 쌓일수록 높아진다
  평생  끝없는 무지개 고리

사용: python3 scripts/make_iap_promo.py  →  docs/screenshots/iap/promo-*.png
아이폰 앱(욕망의 무지개)도 같은 상품 사다리라 같은 그림을 쓴다 — 그쪽 레포의 같은 자리에 복사한다.
"""
import math
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs/screenshots/iap"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
S = 1024

# Theme.swift 의 무지개 (시스템 색)
RAINBOW = ["#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#30B0F0", "#007AFF", "#5856D6", "#AF52DE"]

BG = """<defs><radialGradient id="bg" cx="50%" cy="45%" r="75%">
<stop offset="0" stop-color="#271838"/><stop offset="1" stop-color="#120A1C"/></radialGradient></defs>
<rect width="1024" height="1024" fill="url(#bg)"/>"""


def monthly() -> str:
    """한 달 달력: 7×5칸, 31일이 차고 나머지는 흐리다. 줄마다 무지개 한 색."""
    cell, gap = 84, 18
    w = 7 * cell + 6 * gap
    h = 5 * cell + 4 * gap
    x0, y0 = (S - w) / 2, (S - h) / 2
    out = []
    for i in range(35):
        r, c = divmod(i, 7)
        filled = i < 31
        color = RAINBOW[r] if filled else "#FFFFFF"
        op = 1 if filled else 0.08
        out.append(f'<rect x="{x0 + c * (cell + gap)}" y="{y0 + r * (cell + gap)}" '
                   f'width="{cell}" height="{cell}" rx="22" fill="{color}" opacity="{op}"/>')
    return "".join(out)


def yearly() -> str:
    """열두 달 막대: 아래에서 위로 쌓이며 높아진다. 층마다 무지개 한 색."""
    heights = [2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8]
    col, cgap, blk, bgap = 52, 12, 52, 12
    w = 12 * col + 11 * cgap
    hmax = 8 * blk + 7 * bgap
    x0 = (S - w) / 2
    base = (S + hmax) / 2  # 막대들의 바닥
    out = []
    for c, n in enumerate(heights):
        for k in range(8):
            y = base - (k + 1) * blk - k * bgap
            x = x0 + c * (col + cgap)
            if k < n:
                out.append(f'<rect x="{x}" y="{y}" width="{col}" height="{blk}" rx="15" fill="{RAINBOW[k]}"/>')
            else:
                out.append(f'<rect x="{x}" y="{y}" width="{col}" height="{blk}" rx="15" fill="#FFFFFF" opacity="0.06"/>')
    return "".join(out)


def lifetime() -> str:
    """끝없는 무지개 고리: 일곱 겹의 원, 둥근 블록으로 끊어 그린다."""
    out = []
    radii = [348, 304, 260, 216, 172, 128, 84]
    for i, r in enumerate(radii):
        circ = 2 * math.pi * r
        n = max(5, round(circ / 110))  # 고리마다 블록 길이가 비슷하게
        seg = circ / n
        dash, gapl = seg * 0.62, seg * 0.38
        # 고리마다 시작점을 조금씩 돌려 벽돌처럼 엇갈리게
        rot = -90 + i * 9
        out.append(f'<circle cx="512" cy="512" r="{r}" fill="none" stroke="{RAINBOW[[0,1,2,3,5,6,7][i]]}" '
                   f'stroke-width="28" stroke-linecap="round" stroke-dasharray="{dash:.2f} {gapl:.2f}" '
                   f'transform="rotate({rot} 512 512)"/>')
    return "".join(out)


def render(name: str, body: str) -> Path:
    html = f"""<!doctype html><html><head><meta charset="utf-8">
<style>html,body{{margin:0;background:#120A1C}}svg{{display:block}}</style></head><body>
<svg xmlns="http://www.w3.org/2000/svg" width="{S}" height="{S}" viewBox="0 0 {S} {S}">{BG}{body}</svg>
</body></html>"""
    OUT.mkdir(parents=True, exist_ok=True)
    target = OUT / f"promo-{name}.png"
    with tempfile.TemporaryDirectory() as tmp:
        page = Path(tmp) / "p.html"
        page.write_text(html)
        subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                        # 프로필을 매번 따로 — 앞 실행이 남긴 잠금에 걸려 둘째부터 실패한다
                        f"--user-data-dir={tmp}/profile",
                        "--force-device-scale-factor=1", f"--window-size={S},{S}",
                        f"--screenshot={target}", page.as_uri()],
                       check=True, capture_output=True)
    return target


if __name__ == "__main__":
    for name, fn in [("monthly", monthly), ("yearly", yearly), ("lifetime", lifetime)]:
        print(render(name, fn()))
