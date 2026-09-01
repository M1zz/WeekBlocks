# 무지개 공방 (macOS)

한 주를 요일과 시간대로 짜는 작업대. 할 일을 끌어다 요일에 놓고 계획 블록으로 만든다.

- **소개 페이지** — https://m1zz.github.io/WeekBlocks/
- **개인정보 처리방침** — https://m1zz.github.io/WeekBlocks/privacy.html
- **릴리즈 노트** — [docs/RELEASE_NOTES.md](docs/RELEASE_NOTES.md)

iOS 앱 **욕망의 무지개** 는 별도 저장소입니다 → https://github.com/M1zz/ScheduleDensity
같은 CloudKit 컨테이너를 쓰므로 두 앱을 함께 수정해야 하는 변경이 많습니다.

## 화면

- **주간 그리드** — 요일 x 시간대. 백로그 할 일을 끌어다 놓으면 계획 블록이 된다.
- **하루 타임라인** — 요일 하나를 세로로 펼쳐 실제 시각으로 본다.
- **고정 루틴** — 수면·식사·회사처럼 빼놓을 수 없는 중요한 시간을 먼저 깐다.
- **백로그** — 할 일과 그 단계. 카테고리로 걸러 본다.
- **전파 계약** — 남에게 알려야 끝나는 일의 전처리와 전파 시점 역산.

## 착수 조건

쪼갤 때 묻는 것은 "이 단계가 전체의 몇 %냐"가 아니라 **"지금 시작할 수 있나"** 다.
근거는 [`TodoSplitAdvisor.swift`](WeekBlocks/TodoSplitAdvisor.swift) 머리주석에 있다.

| 속성 | 뜻 | 기본 시간 |
|---|---|---|
| 바로 | 먼저 할 것도 정할 것도 없다 | 15분 |
| 펼치고 | 자료를 펼쳐야 시작된다 | 30분 |
| 몰입해서 | 끊기면 다시 올라와야 한다 | 1시간 |
| 정하고 | 안 정한 것이 막고 있다 | 30분 |
| 기다림 | 내 손을 떠나 있다 | 내 시간 아님 |

시간은 **아래에서 위로** 쌓인다. 상위 할 일의 시간은 단계들의 합이다.

## 타깃

| 타깃 | 번들 ID | 설명 |
|---|---|---|
| `WeekBlocks` | `com.devkoan.ScheduleDensityApp` | 본체 (macOS 14+) |
| `TodoShareExtension` | `...TodoShare` | 공유 메뉴에서 백로그에 추가 |

## 빌드

프로젝트 파일은 [XcodeGen](https://github.com/yonaskolb/XcodeGen)으로 생성한다.

```sh
xcodegen generate --spec WeekBlocks.project.yml
xcodebuild -project WeekBlocks.xcodeproj -scheme WeekBlocks \
  -destination 'platform=macOS' build
```

`.xcodeproj`를 직접 고치지 말고 `WeekBlocks.project.yml`을 고친 뒤 재생성한다.

## 두 저장소를 함께 고쳐야 하는 것

다음 파일은 [ScheduleDensity](https://github.com/M1zz/ScheduleDensity) 저장소에 **같은 내용으로 복제**되어 있다.
한쪽만 고치면 두 앱의 동작이 갈라진다.

- `TodoSplitAdvisor.swift`
- `TodoTree.swift`
- `TodoTips.swift`
- `BacklogItem+Label.swift`

`BacklogItem` / `BacklogCategory` 는 같은 CloudKit 스키마를 쓰므로 **필드 추가·삭제는 반드시 양쪽 동시에** 한다.
전파 계약 필드는 맥에만 있으므로 전부 옵셔널 또는 기본값이다.

## 데이터

- SwiftData 기본 스토어, CloudKit `iCloud.com.devkoan.ScheduleDensity` (private)
- 공유 익스텐션 통로: App Group `QGAQ3AY3R3.group.com.devkoan.ScheduleDensity`
  (맥의 App Group ID는 iOS와 달리 팀 ID가 앞에 붙는다)

> ⚠️ `ModelConfiguration`에 `groupContainer: .none` 이 명시돼 있다.
> App Group entitlement가 붙으면 SwiftData 기본 저장 위치가 앱 샌드박스에서 App Group으로 옮겨가서,
> 이미 배포된 사용자의 루틴·계획·백로그를 못 찾고 전부 사라진 것처럼 보인다. 빼지 말 것.

## 문의

mizzking75@gmail.com
