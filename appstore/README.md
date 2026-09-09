# 앱스토어 스크린샷 (영어)

App Store Connect ▸ 앱 스토어 ▸ **English (U.S.)** 의 미리보기·스크린샷 칸에 올리는
맥 스크린샷 6장. 결과물은 [`en/`](en) 에 **2880 × 1800** PNG 로 들어 있다.

| 파일 | 무엇을 말하는가 | 화면 |
|---|---|---|
| `01-week.png` | 168시간에서 고정 루틴을 뺀 나머지가 이번 주에 쓸 수 있는 전부다 | 주 요약 + 블록으로 보기 |
| `02-drag.png` | 할 일을 요일로 끌어다 놓으면 계획 블록이 된다 | 블록으로 보기 + 할 일 (드래그 중) |
| `03-timeline.png` | 하루를 24시간 자 위에 펼쳐 틈과 겹침을 본다 | 시간축으로 보기 |
| `04-steps.png` | 끝이 닫히는 크기로 쪼갠다 — 두 질문 | 단계 시트 |
| `05-timer.png` | 지금 하는 것과 남은 시간 | 타이머 창 |
| `06-review.png` | 한 주를 체크리스트로 닫는다 | 주간 회고 시트 |

맥 스크린샷은 1280×800 · 1440×900 · 2560×1600 · 2880×1800 중 하나여야 하고
**한 벌 안에서는 크기가 같아야 한다.** 여기 것은 전부 2880×1800 이다.

## 다시 만들기

```sh
cd appstore
node build.mjs           # index.html 을 쓰고 en/*.png 를 그린다
node build.mjs --html    # 브라우저로 들여다볼 index.html 만
```

Playwright 의 Chromium 으로 그린다. 전역 설치본을 쓰려면
`NPM_GLOBAL_ROOT=$(npm root -g) node build.mjs`.

## 이것은 실행 화면이 아니다

맥이 없는 자리에서 만들었으므로 **앱을 띄워 찍은 것이 아니라 그린 것**이다.
대신 그리는 근거를 전부 소스에서 가져왔다.

- 팔레트 — [`WeekBlocks/Theme.swift`](../WeekBlocks/Theme.swift) 의 무지개 7색
- 낱말 — [`WeekBlocks/Localizable.xcstrings`](../WeekBlocks/Localizable.xcstrings) 의 `en` 쪽을 **그대로**
- 배치 — `ContentView` · `WeekGridView` · `DayTimelineView` · `TodoStepsView` ·
  `TimerView` · `ReflectionView`
- 표제 문구 — [`docs/STORE_NOTES_1.1.2.txt`](../docs/STORE_NOTES_1.1.2.txt) 의 영어 설명
- 예시 데이터 — 온보딩이 권하는 그 넷 (`OnboardingView.suggestions`).
  잠 23:00+8h 매일, 끼니 주 17.5h 하루 3번, 일 평일 09:00+9h, 운동 월·수·금 07:00+1h.
  루틴 121.5h → 남은 자유 46.5h. 요일 칸의 차례·겹침 접기·남은 시간은
  `TimelineLayout` 과 같은 규칙으로 계산해 그린다.

**맥에서 실제로 찍을 수 있게 되면 이걸로 갈아 끼우는 것이 낫다.**
그때까지는 화면이 바뀌면 `build.mjs` 의 해당 자리도 같이 고쳐야 어긋나지 않는다.
