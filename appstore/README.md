# 앱스토어 스크린샷

App Store Connect ▸ 앱 스토어 ▸ 각 언어의 미리보기·스크린샷 칸에 올리는 맥 스크린샷.
이 앱이 말하는 두 언어를 각각 여섯 장씩 냅니다.

- 한국어 — [`ko/`](ko)
- English (U.S.) — [`en/`](en)

전부 **2880 × 1800** PNG 입니다. 맥 스크린샷은 1280×800 · 1440×900 · 2560×1600 ·
2880×1800 중 하나여야 하고 **한 벌 안에서는 크기가 같아야 합니다.**

| 파일 | 무엇을 말하는가 | 화면 |
|---|---|---|
| `01-week` | 168시간에서 고정 루틴을 뺀 나머지가 이번 주에 쓸 수 있는 전부다 | 주 요약 + 블록으로 보기 |
| `02-drag` | 할 일을 요일로 끌어다 놓으면 계획 블록이 된다 | 블록으로 보기 + 할 일 (드래그 중) |
| `03-timeline` | 하루를 24시간 자 위에 펼쳐 틈과 겹침을 본다 | 시간축으로 보기 |
| `04-steps` | 끝이 닫히는 크기로 쪼갠다 — 두 질문 | 단계 시트 |
| `05-timer` | 지금 하는 것과 남은 시간 | 타이머 창 |
| `06-review` | 한 주를 체크리스트로 닫는다 | 주간 회고 시트 |

## 다시 만들기

```sh
cd appstore
node build.mjs           # index-{en,ko}.html 을 쓰고 en/*.png · ko/*.png 를 그린다
node build.mjs --html    # 브라우저로 들여다볼 HTML 만
```

Playwright 의 Chromium 으로 그립니다. 전역 설치본을 쓰려면
`NPM_GLOBAL_ROOT=$(npm root -g) node build.mjs`.

말은 `build.mjs` 의 `STRINGS` 한 곳에만 있습니다. 화면을 그리는 코드는 두 언어가
같은 것을 쓰므로, 배치를 고치면 양쪽이 함께 따라옵니다.

## 이것은 실행 화면이 아니다

맥이 없는 자리에서 만들었으므로 **앱을 띄워 찍은 것이 아니라 그린 것**입니다.
대신 그리는 근거를 전부 소스에서 가져왔습니다.

- 팔레트 — [`WeekBlocks/Theme.swift`](../WeekBlocks/Theme.swift) 의 무지개 7색
- 낱말 — [`WeekBlocks/Localizable.xcstrings`](../WeekBlocks/Localizable.xcstrings).
  한국어는 열쇠 그 자체이고, 영어는 그 열쇠의 `en` 값을 **그대로** 옮겼습니다.
- 배치 — `ContentView` · `WeekGridView` · `DayTimelineView` · `TodoStepsView` ·
  `TimerView` · `ReflectionView`
- 표제 문구 — [`docs/STORE_NOTES_1.1.2.txt`](../docs/STORE_NOTES_1.1.2.txt) 의 설명
- 예시 데이터 — 온보딩이 권하는 그 넷 (`OnboardingView.suggestions`).
  잠 23:00+8h 매일, 끼니 주 17.5h 하루 3번, 일 평일 09:00+9h, 운동 월·수·금 07:00+1h.
  루틴 121.5h → 남은 자유 46.5h. 요일 칸의 차례·겹침 접기·남은 시간은
  `TimelineLayout` 과 같은 규칙으로 계산해 그립니다.

글꼴은 SF Pro 와 Apple SD Gothic Neo 를 못 담으므로 대신 Inter(라틴)와
Pretendard(한글)를 받아 씁니다. 둘 다 SIL OFL 이고, 저장소에는 안 담습니다.

**맥에서 실제로 찍을 수 있게 되면 이걸로 갈아 끼우는 것이 낫습니다.**
그때까지는 화면이 바뀌면 `build.mjs` 의 해당 자리도 같이 고쳐야 어긋나지 않습니다.
