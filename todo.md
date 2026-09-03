# ScheduleDensity 패밀리 — 할 일 목록

iOS 앱(ScheduleDensity)과 macOS 앱(WeekBlocks)을 하나의 Xcode 프로젝트에서
두 개의 타깃으로 관리하는 "같은 패밀리" 구조.

## 완료
- [x] WeekBlocks 소스를 `WeekBlocks/` 폴더로 흡수
- [x] `ScheduleDensityApp.xcodeproj`에 macOS 타깃 `WeekBlocks` 추가
- [x] WeekBlocks 타깃에 macOS 빌드 설정(SDKROOT/배포타깃) 오버라이드
- [x] 두 타깃 모두 빌드 성공 검증 (iOS / macOS)
- [x] 명명 전면 통일: macOS 번들 ID `com.devkoan.ScheduleDensityApp`, 표시이름 `ScheduleDensity`
- [x] WeekBlocks iCloud(CloudKit) 연동: 공유 컨테이너 `iCloud.com.devkoan.ScheduleDensity`
      (entitlements + SwiftData `cloudKitDatabase: .private(...)`, 빌드/서명 검증, 컨테이너 자동 등록됨)
- [x] iOS 기준 디자인 통일 (표시이름 "무지개 공방")
      - 컬러: `Theme.swift` 신설 — iOS laneColors와 동일한 7색 무지개 hex 팔레트 + `Color(hex:)` + 밀도 색 스케일
      - `paletteColor`/`routineColorOptions`를 iOS 시스템 색 hex로 통일, AccentColor = 시스템 블루 #007AFF
      - 톤: 전 UI 반말 → iOS 존댓말로 통일 (ContentView/BlockEditor/ConcretenessChecker/Backlog/Reflection/Routines)
      - UX: 툴바에 설정(gearshape)·더보기(ellipsis.circle: 루틴 추가/샘플/전체 삭제) 추가, `SettingsView` 신설(iOS Form/Section 미러링)

- [x] 고정 루틴 워크플로 강제 (macOS)
      - 고정 루틴 추가 시 주간 그리드에 자동 배치 (`onChange(routines.count)` → 즉시 occurrence 시딩)
      - 고정 루틴 삭제 잠금: RoutineRow 휴지통 → 잠금 아이콘, 편집기 삭제 버튼 숨김 (이름·요일 편집은 가능)
      - 게이트: 고정 루틴이 하나라도 있어야 백로그·계획 블록 추가 가능 (없으면 잠금 + 안내)
      - 레이아웃: 루틴 섹션을 그리드/백로그 위로 이동 (루틴 먼저 → 계획 흐름)
- [x] 요일별 하루 24시간 타임라인 (`DayTimelineView.swift`)
      - 7요일 가로 막대 + 0/6/12/18/24 축, 시간 격자(24칸)
      - 고정 루틴 정확한 시각 배치(자정 넘김 분할), 계획 블록은 시간대 빈 구간 패킹
      - 요일별 "자유 Xh"(초과 시 빨강) 표시
      - 절대 겹침 없음: 통합 그리디 패킹(루틴+계획 모두 통째로, 빈 구간에만 배치, 시각은 근사치)
- [x] 주간 쿼터 자동 계산 표시 (일 평균 + 회당)
      - Routine에 `sessionsPerDay`(하루 횟수) 추가, `dailyQuotaHours` + `formatDuration` 헬퍼
      - scheduleDescription: "주 17.5h · 일 평균 2시간 30분 · 회당 약 50분"
      - 편집기에 하루 횟수 스테퍼 + 실시간 계산 미리보기, 기본 식사 시드 = 3회

- [x] 백로그 주(week) 단위 재구성
      - BacklogItem에 weekStartDate 추가, 메인 백로그는 "이번 주"만 표시
      - "전체 백로그" 시트(AllBacklogView): 주별 그룹, 지난 주 미완료 → "이번 주로 가져오기", 헤더에 이월 개수 배지
      - "할 일 작성" 시트(BacklogComposerView): TODO식 입력(Enter 연속 추가), 행별 카테고리·시간 편집, 카테고리 관리 포함
      - 메인의 인라인 빠른추가 바 제거(동선 단축)

- [x] App Store 심사 Guideline 4(Design) 대응 — 창 닫은 뒤 다시 열기 (macOS)
      - `WeekBlocksApp.swift`: `WindowGroup` → `Window("무지개 공방", id: "main")` 단일 창 씬으로 교체
      - 윈도우 메뉴에 "무지개 공방" 항목이 자동 등록되어 창을 닫아도 메뉴/Dock 클릭으로 재오픈 가능
      - macOS 빌드 검증 완료

- [x] WeekBlocks 지원 페이지 제작 + GitHub Pages 배포
      - `docs/index.html`: 기능/사용법/FAQ/개인정보/문의 (무지개 팔레트·존댓말)
      - Pages 소스 = main `/docs`, URL https://m1zz.github.io/ScheduleDensity/
      - README(main·dev)에 지원 페이지 링크 추가

## 완료 (2026-07-08)
- [x] iOS 앱(ScheduleDensityApp)도 같은 공유 컨테이너로 iCloud 연동
      - entitlements `iCloud.com.devkoan.ScheduleDensity` + Background Modes(Remote notifications)
      - WeekBlocks 모델 6종을 iOS 타깃에 공유 컴파일, `cloudKitDatabase: .private(...)`
      - Event는 별도 로컬 전용 ModelConfiguration으로 유지 (CloudKit 미적용 — 기존 데이터 그대로)
- [x] iOS에 '할 일' 탭 추가 — 간단 Todo(내 할 일: 맥 백로그와 동기화, isCompleted 체크)
      - Event 스토어·WeekBlocksStore 미러와 분리된 별도 컨테이너("WeekBlocksTodos", BacklogItem·BacklogCategory만 CloudKit private)
- [x] 가족 공유 — CloudKit 커스텀 존("FamilyTodos") + 존 전체 CKShare
      - `FamilyShareStore.swift`(공용): 소유자=개인 DB, 참가자=공유 DB, 초대 링크(publicPermission .readWrite)
      - iOS: 할 일 탭 안 '가족' 세그먼트 / macOS: '가족 할 일' 섹션
      - 초대 수락: iOS SceneDelegate·macOS NSApplicationDelegate + `CKSharingSupported`
      - ⚠️ 프로덕션 배포 전 CloudKit Console에서 스키마 deploy 필요 (BacklogItem 새 필드 + FamilyTodo 레코드 타입)

## 할 일 뎁스(단계) — 2026-08-22, iOS·맥 동시 구현 (양쪽 빌드 성공)
할 일 하나를 100%로 놓고, 그 안을 '일이 되어야 하는 순서대로' 쪼갠다.
체크로 끝내는 게 아니라 **탭하면 다음 단계로 바뀐다**. 비중은 예상 시간 비율로 자동.

- [x] 공유 코어 `TodoTree.swift` — 순수 로직, iOS `Shared/`와 맥 `WeekBlocks/`에 **같은 파일로 복제**
      (부모-자식 색인 / 잎 순서 / 시간 합 / 비중 / 진행률 / advance·rewind / 조상 롤업)
      - 비중 = 예상 시간 비율. 중첩되면 조상 비중이 곱해진다 (50% 안의 60% → 30%)
      - 부모 완료 = 자식 전부 완료(자동 롤업), 부모 시간 = 자식 시간 합(자동 재계산)
      - 부모가 사라진 고아 단계는 최상위로 취급, 순환 참조는 깊이 12에서 멈춤
      - swiftc 단독 검증 통과 (비중·진행률·탭 전진·되돌리기·시간 변경·순환)
- [x] 모델: `BacklogItem.parentToken: String?` 추가 (부모의 dragToken). 양쪽 동일
- [x] iOS 할 일 탭: 목록은 최상위만, 한 줄에 '지금 할 단계 + 진행률 + n단계 중 m번째'
      - 체크 원 탭 = 지금 단계 끝내고 다음으로 / 완료된 줄 다시 탭 = 마지막 단계 되돌리기
      - 줄을 누르면 `TodoDetailView` — 단계 트리, 추가·이름/시간 수정·순서 이동·삭제
      - '오늘로 배정'은 제목은 최상위 그대로(배지·취소가 계속 맞아야 함), 시간만 현재 단계 기준
- [x] 위젯: 스냅샷에 `stepTitle`·`progress` 추가(옛 스냅샷 호환), 홈 위젯 2줄·잠금 인라인에 단계 표시
- [x] 맥 백로그: 카드에 지금 할 단계·진행률, 카드의 단계 버튼/컨텍스트 메뉴로 전진·되돌리기
      - `TodoStepsView` 시트에서 단계 추가·시간(스테퍼)·순서·삭제
      - 요일로 드래그: 단계가 있으면 **지금 단계만** 블록으로 올리고 항목은 백로그에 남긴다
        (단계가 없는 할 일은 종전대로 통째로 옮겨지고 백로그에서 사라진다)
      - 할 일 작성 시트·전체 백로그도 최상위만 나열, 이월·삭제는 단계까지 통째로

- [ ] ⚠️ 배포 전 CloudKit Console에서 `BacklogItem.parentToken` 필드 스키마 deploy
- [ ] 런타임 검증 미완 — 실제 기기에서 맥↔아이폰 단계 동기화 확인 필요
- [ ] 가족 할 일(FamilyTodo, CKRecord 별도 타입)은 아직 1뎁스 그대로

### 쪼개기 도우미 — 조각 시간 연구 반영 (2026-08-23)
사용자가 감으로 쪼개지 않도록 앱이 판정과 힌트를 준다. 공유 코어 `TodoSplitAdvisor.swift`
(iOS `Shared/` ↔ 맥 `WeekBlocks/`, 같은 파일 복제).

- [x] 단계 판정: 조각(≤15분) / 짧은 덩어리 / 덩어리(≥45분) + 제목 낱말 사전
      - 시동 비용 큰 낱말(쓰기·구현·설계·학습…)이 조각 시간에 들어가면 경고 (Mark 2008, 재개 23분)
      - 2시간 넘는 잎 단계는 "한 번에 안 끝남" 경고 (Leroy 2009, 주의 잔여물)
      - 결정 낱말(정하기·고민·검토)은 조각에서 안 닫힘 → 덩어리로 안내
      - 몸 낱말(운동·스트레칭·계단)은 조각 OK (Stamatakis 2022 VILPA)
      - 배수구 낱말(SNS·유튜브·피드)은 "일이 아니라 조각이 새는 곳"
- [x] 구성 조언: 조각 단계 없음 / 마감(닫기) 단계 없음 / 너무 큰 단계 /
      짧게 잡힌 덩어리 작업 다수 / 결정이 작업 뒤에 있음 / 잘 쪼갠 경우 칭찬
- [x] 쪼개기 도우미 뼈대 4단계 (결정→준비→작업→마감) 한 번에 생성 — 양쪽
- [x] 표시: 단계 행·입력 중 실시간 판정·수정 시트(iOS)·맥 시트와 백로그 카드에 조각/덩어리 태그
      할 일 목록(iOS)·백로그 카드(맥)의 '지금 할 단계'에도 태그 → 5분 생겼을 때 집을 것이 보인다
- [x] swiftc 단독 검증 (판정 10종·구성 조언 3종)
- [x] (아이디어) "지금 5분 있어요" 필터 — 아래 라벨 필터로 구현

### 시간을 위에서 아래로 + 라벨 (2026-08-23)
"상위 일이 몇 시간 걸리는지 예상치를 꼭 받고, 하위 일들이 그걸 나눠 가진다."
시간의 방향이 뒤집혔다 — 전에는 부모 시간 = 자식들 합(아래→위)이었다.

- [x] `TodoTree` 예산 계산 재작성 (양쪽 레포 동일 파일)
      - 부모의 예상 시간이 100%. 자식들의 합은 **언제나** 부모의 시간
      - 새 단계는 기본 N분의 1 (`giveInitialShare`), 첫 단계는 부모 전체를 물려받음
      - 한 단계를 직접 조정하면(`setHours`/`setWeight`) 나머지가 남은 몫을 다시 나눔 → 합계 100%
      - 직접 정한 단계는 `isManualWeight`로 잠기고 자동 재분배에서 빠짐 (`releaseManual`로 해제)
      - `setTotalHours` = 전체 시간 변경 시 아래 단계들이 비율 유지한 채 함께 조정
      - `splitEvenly`(N분의 1 리셋) / `fit`(삭제·동기화 어긋남 복구)
      - 분 단위 정수 계산 + 남는 분 앞에서부터 배분 → 60분을 7단계로 나눠도 합이 정확히 100%
      - `rollUp`은 완료 상태만 굴린다(시간은 더 이상 위로 안 올라감), `syncHours` 제거
      - swiftc 단독 검증 통과 (N분의 1·직접 조정·잠금 유지·전체 시간 변경·나머지 분·삭제·리셋·진행률)
- [x] 라벨 = 예상 시간 (`TodoLabel`: 지금 바로 15분 / 앉아서 한 번 30분 / 집중 한 판 1시간 /
      시간 잡고 2시간 / 반나절 4시간). 적을 때 **반드시 하나 고르게** 해서 예상치를 꼭 받는다
      - 모델: `BacklogItem.labelRaw`·`isManualWeight` 추가 (옵셔널/기본값 = 라이트웨이트 마이그레이션)
      - 라벨 없는 옛 항목은 예상 시간에서 가장 가까운 라벨로 짐작 (`TodoLabel.nearest`)
- [x] 화면을 '라벨 먼저'로 — 작은 조언 글이 너무 많아 바로 못 하던 문제
      - 목록·단계 행에 라벨 칩(아이콘+이름+시간), 단계 행에 비중 막대 + 큰 % 숫자
      - 긴 쪼개기 조언은 접어 두고(경고 개수만 표시), 행에는 경고 한 줄만
      - iOS 상세 헤더에서 전체 예상 시간을 바로 고침, 단계 섹션에 'N분의 1로' 버튼
      - 단계 추가 시 '자동 N분의 1' 또는 라벨을 골라 그만큼 떼어 주기
- [x] "지금 5분 있어요" 필터 — 목록 위 라벨 칩으로 걸러 보기 (지금 할 단계의 라벨 기준)
- [ ] ⚠️ 배포 전 CloudKit Console에서 `BacklogItem.labelRaw`·`isManualWeight` 스키마 deploy
- [ ] 런타임 검증 미완 — 실기기에서 맥↔아이폰 비중·라벨 동기화 확인 필요


### 조언은 전부 TipKit으로 (2026-08-23)
화면에 조언을 상시로 깔면 정보가 많아 못 시작한다. 알려줘야 하는 건 전부 팁으로 뺐다.
공유 파일 `TodoTips.swift` (iOS `Shared/` ↔ 맥 `WeekBlocks/`, 같은 내용 복제, 두 pbxproj에 등록).

- [x] `TodoTips.configure()` — 앱 진입점(`ScheduleDensityApp.init` / `WeekBlocksApp.init`)에서 한 번
      (`displayFrequency: .immediate` — 어차피 팁마다 한 번 닫으면 끝)
- [x] 규칙 있는 팁 (`@Parameter`로 조건 저장, 조건 맞을 때만 등장)
      - `LabelPickTip` — 라벨을 한 번도 안 골라봤을 때 "라벨이 곧 예상 시간입니다"
      - `FragmentFilterTip` — 할 일 3개 이상 쌓이면 "지금 10분 났을 때" 라벨 필터 안내
      - `ShareSplitTip` — 단계가 둘 이상 생기면 N분의 1·합계 100% 규칙 설명
      - `LockedShareTip` — 비중을 처음 직접 정하면 자물쇠의 뜻 설명
- [x] 내용이 그때그때 다른 팁 (id를 종류별로 따로 둬서, 닫으면 **그 종류만** 안 뜬다)
      - `SplitHintTip` — 구성 조언(`SplitHint`) 중 가장 중요한 하나. `SplitHint.code` 신설이 팁 id
      - `StepWarningTip` — 단계 경고는 **지금 할 단계 하나**에만. 모든 줄에 깔지 않는다
- [x] 걷어낸 것: 상세 화면의 '쪼개기 조언' 섹션(DisclosureGroup)과 `HintRow`,
      단계 줄마다 붙던 경고·이유 문구, 입력 중 실시간 판정 문구
- [x] 팁이 이미 닫힌 자리에 빈 줄이 남지 않도록 `shouldDisplay`로 걸러서 그린다
- [x] 설정 > 조언 > '할 일 조언 다시 보기' (`Tips.resetDatastore`) — 양쪽 앱
- [x] 시뮬레이터 실행 확인: TipKit 데이터스토어 로드 OK, 실행 중 오류 없음
- [ ] 팁이 실제로 뜨는 모습은 손으로 확인 필요 (입력창에 제목 입력 → 라벨 줄 위)

## ⚠️ 두 레포 공유 모델 드리프트 (2026-08-22 확인)
맥에 `전파 계약`(287f17f)이 들어가면서 공유 모델이 갈라졌다. iOS는 아직 못 따라감:
- `BacklogItem` — 맥에만 전파 필드 13개 (needsBroadcast/deadline/latestDate/…)
- `PlanBlock` / `BacklogCategory` / `Routine` — 맥이 더 많음
- iOS에 없는 필드라 아이폰에서는 전파 항목이 그냥 일반 할 일로 보인다 (데이터는 안 깨짐)
- [ ] iOS에 전파 계약 모델·화면 반영 여부 결정 (모델만 맞출지, 화면까지 낼지)

## 정리 필요
- [ ] 기존 독립 프로젝트 `/Users/leeo/Documents/workspace/code/WeekBlocks` 제거 (이 저장소로 흡수 완료 후)
- [ ] (선택) WeekBlocks 내부 타깃/스킴명도 ScheduleDensity 계열로 변경 — Xcode에서 rename 권장(수기 pbxproj 위험)

## iOS 시각화 연동 (WeekBlocks 데이터 → 욕망의 무지개 밀도 뷰)
방향 확정: **같은 iCloud 계정(private DB)** 전제, iOS는 **읽기 전용 소비자**.
WeekBlocks `Routine`/`PlanBlock`을 메모리상 `Event`로 변환해 기존 밀도 파이프라인 재사용.

- [ ] 1. 공유 모델: `WeekBlocks/`의 `Models.swift`·`Routine.swift`·`PlanBlock.swift`(+필요 시 BacklogItem 등)를 iOS 타깃 멤버십에 추가 (복붙 금지, 단일 소스)
      - ⚠️ `Theme.swift`(Rainbow/Color(hex:))도 함께 필요 — iOS에 같은 헬퍼가 있으면 중복 정의 충돌 점검
- [ ] 2. 별도 읽기 전용 store: iOS에 WeekBlocks 모델용 `ModelConfiguration`(CloudKit private, 컨테이너 `iCloud.com.devkoan.ScheduleDensity`) 추가. 기존 `Event` store는 **그대로 둠**
      - entitlements에 iCloud/CloudKit + 컨테이너 ID + Background Modes(Remote notifications)
- [x] 3a. 어댑터 순수 코어: `WeekBlocksAdapter`(타깃 의존성 없음) — `WBRoutineInput`/`WBBlockInput` → `WBVisualEvent`
      - PlanBlock → 해당 주 단일일(weekStart+요일, hoursPerDay=durationHours)
      - Routine.fixed → 주간 반복(selectedWeekdays, hoursPerDay=durationHours)
      - Routine.quota → 7일 평균 부하 밴드(hoursPerDay=weeklyHours/7)
      - 요일 변환 mon0→iOS weekday, 날짜·색·필터 모두 swiftc로 단위 검증 통과 ✅
- [x] 1·2. 모델 공유·store: Models/Routine/PlanBlock을 iOS 타깃에 포함, Routine 색상헬퍼는 Theme(macOS)로 분리.
      `WeekBlocksStore`(Services) = 별도 읽기전용 CloudKit 컨테이너(`iCloud.com.devkoan.ScheduleDensity`), Event 스토어와 분리.
      entitlements 컨테이너 추가 + Background Modes(Remote notifications). pbxproj에 어댑터/스토어 정식 포함.
- [x] 3b. 배선: WeekBlocksStore.loadVisualEvents()가 Routine/PlanBlock→어댑터→[Event](insert 금지).
- [x] 4. 표시: ScheduleViewModel.fetchEvents()에 합쳐 투입(전 화면 반영) + SettingsView "무지개 공방 계획 표시" 토글(기본 ON).
- [ ] ⚠️ 런타임 검증 미완: 같은 iCloud 계정 실기기/시뮬레이터에서 Mac↔iOS 실제 동기화 확인 필요.
- [ ] 5. 동기화 상태: iCloud 미로그인/첫 다운로드 지연/오프라인 빈 상태 UI 처리, 원격 변경 시 갱신(현재는 캐시가 dataRefreshTrigger에만 반응).
- [ ] (개선) 어댑터가 쿼터를 7일 평균으로 뭉갬 → '하루 흐름'까지 보이려면 TimelineLayout 공유 코어화.
- [ ] 6. (보류) successCriteria·deliverable·reviewStatus 노출 여부 결정

## macOS(WeekBlocks) 피드백 반영 (2026-06-23) — macOS 빌드 성공
- [x] 1. 타임라인 격자 6h → 3h 세분화 (DayTimelineRow 격자 major 3h, HourAxis 0·3·6…24)
- [x] 2. 짧은 블록 텍스트 — 임계값 30→18 + minimumScaleFactor + 툴팁에 계획 이름 노출
- [x] 3. 유연 쿼터 대비 강화 — 고정 위에 겹칠 때 흰 테두리 링 + 채움 0.20→0.32
- [x] 4. '구체성 체크' 버튼 제거 — 편집기 진입 시 항상 실시간 피드백
- [x] 5. 계획 블록을 다른 요일로 드래그 이동 (BlockChip draggable + 드롭에서 day 변경)
- [x] 6. '이번 주 계획' 순서 = '요일별 하루' 타임라인 순서 일치
      - DayPlanItem을 occurrence 기반으로(고정/끼니세션/블록) 재정의, TimelineLayout.segments의 seg.start로 정렬
      - 자정 넘긴 고정 루틴(수면)은 조각마다 따로 → 위·아래 두 번 표시
      - 유연 쿼터(끼니)는 다른 일정과 안 겹치는 세션만 자기 시각에 표시(겹치면 접음), 부제에 세션 시각

## 완료 (2026-07-30) — 전파 필요 항목 전처리 + 데드라인 역산 전파 시점
전제: 전파가 필요한 이유는 사회성·실력이 아니라 **정보 비대칭**이다. 나는 진행 상황을 알고
상대는 0인데 실패의 피해는 함께 진다. 그래서 전파할 것은 진척도가 아니라 **판단**이고,
상대가 밖에 그대로 옮길 수 있는 문장이어야 한다. 설익은 산출물 노출은 비용이 크므로
**경계(계약)만 고정하고 내부는 자유롭게** 굴리는 구조로 만들었다.

- [x] `BacklogItem`에 전파 계약 필드 13개 추가 (전부 기본값/옵셔널 — CloudKit 라이트웨이트 마이그레이션)
      needsBroadcast, deadline, broadcastAudienceRaw, broadcastRecipient, handoffForm,
      earliestDate/latestDate, broadcastConfidenceRaw, openVariable, variableResolveDate,
      noSignalRuleAgreed, broadcastContractVerified, sentCheckpointsRaw
- [x] `BroadcastPlanner.swift` — 순수 로직(Foundation only, iOS 타깃 공유 가능)
      - 대상 4종(의사결정자/하류 동료/동급 동료/클라이언트) — 강조점과 리드타임이 다름
      - **역산 기준은 데드라인이 아니라 '늦어도' 보장일** (상대에게 약속한 날이 실제 기준)
      - 리스크 게이트 리드타임 = 기간×25% + 대상 가산(의사결정자 2·클라이언트 3·하류 1) +
        확신도 가산(낮음 3·보통 1), 상한 min(10일, 기간×70%)
      - 시점 5종: 착수 선언 / 중간 판단(3주 초과 시 2주 간격, 최대 4회) / 변수 판명 /
        리스크 게이트 / 최종 확정(약속일 −1)
      - 주말 처리: 마감에 묶인 게이트·확정은 앞 평일로 당기고, 중간 판단은 뒤 평일로 미룸
      - 같은 날 중복은 우선순위로 1개만 (착수 > 게이트 > 확정 > 변수 > 중간)
      - 착수 직후/게이트 직전에 붙는 중간 신호는 버림 (통수만 늘고 정보가 없음)
      - 시점별 복사용 문장 생성 + 어디 한 곳에 둘 '네 줄' 카드
- [x] `BroadcastContractChecker` — 전파 항목 전용 전처리 (일반 항목의 ConcretenessChecker에 대응)
      대상·데드라인·넘길 형태 필수, **단일 날짜 금지(빠르면/늦어도 둘 다)**, 보장일이 데드라인
      초과 금지, 미확정 변수 1개 + 판명일 필수, 넘길 형태의 모호 표현("정리해서" 등) 차단
- [x] `BroadcastContractView.swift` — 계약 편집기 시트 + 역산 타임라인 + 문장/네 줄 복사(NSPasteboard)
- [x] 계약 확정을 막는 칸을 빨간색으로 지목 — "왜 확정이 안 되는지"가 그 자리에서 끝나게
      - `BroadcastContractField`(누구에게/데드라인/넘길 형태/두 날짜/미확정 변수/판명되는 날) 신설,
        `BroadcastContractIssue.field`로 각 검사 메시지를 해당 칸에 연결
      - 표시 4겹: 섹션 제목 빨간색 + '미작성' 배지 / 입력칸 우측 ❗ / 섹션 안 빨간 사유 /
        푸터 '미작성: 누구에게 · 두 날짜' (확정 버튼 옆이라 왜 안 눌리는지 바로 보임)
      - 두 날짜는 비어 있는 쪽만 짚고, 순서·범위 오류는 제목+사유로 안내
      - advisory(참고사항)는 `field == nil`로 두어 빨간 표시에서 제외 — 저장을 막지 않으므로
      - swiftc 검증: 8개 케이스 전부 기대한 칸에만 표시, 미지정(field == nil) 차단 메시지 0개
- [x] `BroadcastPlanSection.swift` — 메인 상단 '전파 필요' 섹션 (없으면 섹션 미표시)
- [x] 백로그와 섹션의 관계 확정: **할 일은 전부 백로그에 남고, 섹션은 그중 전파 필요한 것만
      골라 비추는 창**이다 (항목을 옮기는 게 아니라 같은 항목이 양쪽에 보인다)
      - 백로그에서 전파 항목이 빠지는 경로 없음 — `weekItems` 필터는 완료/주차만 본다
      - 섹션은 전파 필요 항목 **전부**를 급한 순으로: 지남 → 오늘 → 예정 → 계약 미확정
        (한때 오늘+지난 것만으로 좁혔다가 되돌림 — 예정인 것이 섹션에서 빠져 안 보였다)
      - 헤더에 상태별 배지(지남 N · 오늘 N · 계약 미확정 N) + "백로그에도 그대로 있습니다"
      - `PendingBroadcastRow`가 `checkpoint: BroadcastCheckpoint?`를 받아 세 상태를 렌더:
        시점 있음(문장 복사·보냈음) / 계약 미확정(주황 + '계약 마치기') / 전파 완료(초록)
      - 백로그 카드의 D-day 배지는 그대로 유지 (백로그만 봐도 상태가 보인다)
- [x] 백로그는 주를 옮겨도 **전부** 보인다 (주 필터 제거)
      - `BacklogSection.weekItems`: 주차 필터 삭제 → 미완료 항목 전부.
        해야 할 일이 보는 주에 따라 나타났다 사라지면 빠뜨린다
      - 표시 순서: 보는 주 → 지난 주(이월, 오래된 것부터) → 앞으로
      - 다른 주 항목엔 상대 주차 캡슐("지난 주" / "2주 전") — 전부 보여주되 어느 주 계획인지는 유지
      - 헤더 "백로그 — 이번 주" → "백로그", 부제에 "보는 주 N개" 추가
      - 작성 시트(BacklogComposerView)도 같은 범위로 통일 — 백로그에 보이는데 편집할 수
        없으면 손댈 방법이 없다. 새 항목은 여전히 보고 있는 주로 들어간다
      - `전체 백로그` 시트는 그대로 (완료 항목 포함 + 주별 그룹 + '이번 주로 가져오기')
      - 드롭 처리는 이미 전체 항목에서 dragToken을 찾으므로 다른 주 항목 드래그도 정상 동작
- [x] 드롭 시 전파 계약 유실 차단 (2 + 3 동시 적용)
      배경: 백로그 항목을 요일에 드롭하면 PlanBlock이 생기고 항목은 삭제된다.
      계약이 함께 넘어가지 않으면 대상·두 날짜·넘길 형태·보낸 시점 기록이 전부 사라졌다.
      - (2) 계약 승계: `BroadcastContract.swift` 신설 — `BroadcastContractHolder` 프로토콜
        + 익스텐션에 접근자/플래너 연결/검사를 **한 곳에** 모음.
        `BacklogItem`·`PlanBlock` 둘 다 conform (저장 필드 13개는 SwiftData 요구로 양쪽에 선언,
        로직은 공용 — 구현이 갈라지지 않게)
      - `copyBroadcastContract(to:)`로 13개 필드 통째 승계. **보낸 시점(sentCheckpointsRaw)까지**
        옮긴다 — 빼먹으면 이미 보낸 전파를 다시 보내라고 뜬다
      - 검증(스크립트): 저장 필드·프로토콜 요구사항·copy 대상이 모두 13/13 일치
      - `BroadcastPlanSection`이 `allBlocks`도 받아 계획 블록의 계약까지 표시.
        블록은 '계획 배치됨' 캡슐로 구분 (백로그에서 찾아도 없으므로)
      - `BroadcastContractView`를 소유자 타입에 대해 제네릭화, 섹션은 `ContractTarget` enum으로 분기
      - (3) 드롭 경고: 전파 계약이 있는 항목을 드롭하면 확인 알럿.
        무엇이 함께 넘어가는지 요약(대상·약속일·보낸/남은 전파·계약 미확정) + "배치하고 계약 유지" / "취소"
      - ⚠️ CloudKit 스키마에 PlanBlock 새 필드 13개 추가 필요 (배포 전 Console deploy)
      - [ ] (선택) BlockEditorView에도 전파 계약 진입점 — 현재는 '전파 필요' 섹션에서만 열 수 있다
- [x] 디자인 정리 — 심볼·장식·중복 정보 제거 (밀도 낮추기)
      - SF Symbols 56 → 12 (BroadcastPlanSection 6→0, BroadcastContractView 19→0, BacklogView 31→12)
        남긴 12개는 전부 기능 컨트롤: 메뉴 선택 체크마크, 디스클로저 chevron, 호버 삭제 ×,
        컬러/아이콘 피커(사용자가 고르는 기능 자체)
      - 캡슐 배지 9 → 2 (남은 2개는 이월 개수·필터 칩 선택 표시)
      - 중복 정보 제거:
        · 계약 편집기에서 같은 오류가 3곳(칸 아래 + 요약 섹션 + 푸터)에 나오던 것 → 칸 아래 + 푸터 2곳
        · 전파 줄에서 날짜 + D-day + 약속일 → 날짜·D-day만 (약속일은 계약 안에 있다)
        · 백로그 카드 배지가 시점+D-day를 반복 → '전파 / 전파 오늘 / 전파 지남 / 계약 미확정' 상태만.
          어느 시점을 언제 보내는지는 '전파 필요' 섹션이 온전히 보여준다
        · 작성 시트 푸터의 계약 미확정 수(섹션 헤더와 동일) 제거
        · 백로그 헤더 '보는 주 N개', 섹션 헤더 '전체 N건'·'백로그에도 그대로 있습니다' 제거
        · 체크포인트 줄의 "오늘 보내세요"(D-day와 같은 말) 제거
      - 긴 설명 푸터 7개를 한 줄로 축약 (이유는 남기고 문단은 걷어냄)
      - 아이콘 버튼 → 텍스트 버튼 (복사/보냄/계약/삭제/전파), 행 여백 확대
- [x] 색으로 전달하던 의미를 전부 말로 옮김 (상태색 제거)
      원칙: 색은 의미를 전달하지 않는다. 색이 하던 말을 문구가 대신한다.
      - 전파 줄: 빨강/주황/초록 tint + 좌측 색 막대 제거 → `dDayLabel`이 "3일 지남"/"오늘"/"D-7"로
        급함을 말하고, 정렬 순서(지남→오늘→예정→미확정)가 나머지를 전달
      - 계약 편집기: 빨간 표시 전부 제거 → 섹션 제목에 "— 미작성"을 붙이고,
        푸터는 "확정하려면 더 필요합니다 — 누구에게 · 두 날짜", 통과 시 "확정할 수 있습니다"
      - 체크포인트 줄: 상태색 제거 → 보낸 것은 "8/6(목) · 보냄", 안 보낸 것은 "8/6(목) · D-7"
      - 백로그 카드: 색 없는 문구로 — 전파 / 전파 D-3 / 전파 오늘 / 전파 지남 / 전파 · 계약 미확정
      - 이월 배지(주황 캡슐) → "전체 백로그 (이월 3)"
      - 작성 시트 전파 버튼: 색 대신 "전파" / "전파 · 미확정" / "전파 안 함"
      - 카테고리 관리: "전파 카테고리" / "전파로 지정"
      - 안 쓰게 된 `BroadcastAudience.colorName/systemImage`,
        `BroadcastConfidence.colorName`, `BroadcastCheckpointKind.systemImage` 삭제
      - 남긴 색: **카테고리 색만** (사용자가 컬러 피커로 고르는 기능 — 상태가 아니라 정체성).
        전파 필터 칩은 상태 필터라 카테고리 색 관례에서 빼고 무채색으로
- [x] BacklogView 연결: 작성 시트 행에 안테나 토글(누르면 즉시 계약 전처리 진입),
      백로그 카드에 다음 시점 D-day 배지, 컨텍스트 메뉴, '전파 필요 N' 필터 칩
- [x] '전파' 카테고리 기본 제공 — 할 일 작성 시 카테고리만 골라도 전파 흐름에 들어온다
      - `BacklogCategory.isBroadcast` 플래그로 판별 (이름 기준이 아니라서 이름을 바꿔도 유지)
      - 기본 시딩(업무/개인/건강/학습) 뒤에 추가 + `didSeedBroadcastCategory`로 **기존 설치에도 한 번 보강**
      - 이 카테고리를 고르면 `needsBroadcast` 자동 ON + 전파 계약 시트 즉시 오픈
        (작성 시트 카테고리 메뉴 / 카드 컨텍스트 메뉴 / 작성 줄 기본 카테고리 전부)
      - 카테고리에서 빼는 건 전파 필요 해제와 다른 동작이라 계약 데이터를 지우지 않음
      - 카테고리 관리에 안테나 토글 — 전파 연결을 다른 카테고리로 옮길 수 있고 항상 1개만 유지
      - `dedupeCategoriesByName`이 중복 병합 시 isBroadcast를 살아남는 쪽으로 승계
      - ⚠️ 카테고리는 항목당 1개뿐 → '전파' 지정 시 '업무'와 겸할 수 없다.
        겸해야 하면 카테고리는 업무로 두고 안테나 토글로 전파를 켜는 경로가 그대로 남아 있다
- [x] 로직 단위 검증(swiftc 직접 실행): 1일·4일·2주·2개월 기간, 대상 4종, 확신도 3종,
      주말 스냅, 검사 실패 케이스 통과. 문장 생성 무한재귀 버그 발견·수정
      (script → midCountLabel → checkpoints → script)
- [x] macOS 빌드 성공 (`CODE_SIGNING_ALLOWED=NO`)
- [ ] ⚠️ UI 런타임 미검증 — 서명 실패로 실행 못 함. 아래 '알려진 문제' 참조
- [ ] (선택) 계획 블록(PlanBlock)에도 전파 계약 적용 여부 결정 — 현재는 할 일(BacklogItem)만
- [ ] (선택) 전파 시점 도착 시 알림(Notification) — '알림/메뉴바 위젯' 항목과 함께

## 완료 (2026-07-31) — 타임라인 수면 숨기기 + 폰트 확대
- [x] '요일별 하루'에서 수면 시간 숨기기 옵션 (설정 → 요일별 하루)
      - `HourWindow`(start/end) 도입 — 타임라인이 0–24 고정이 아니라 '창'을 그린다.
        격자·세그먼트 좌표·드래그 환산(`translation/w * window.span`)·시간 축이 모두 창 기준
      - `TimelineLayout.visibleWindow(fixedRoutines:blocks:hideSleep:)` — 하루 **양끝**의 수면만 잘라냄.
        한가운데 낮잠은 안 자름(가운데를 도려내면 축이 끊겨 시각을 읽을 수 없다)
      - 수면 판별은 이름(수면·잠·취침·sleep) — 모델 필드 추가 없이 기존 데이터도 그대로 동작
      - 안전장치: 잘라낼 자리에 다른 고정 루틴이나 시각 지정 계획이 걸치면 창을 도로 넓힘.
        시각 미지정 계획은 빈 구간(=수면 밖)에 배치되므로 창에 영향 없음
      - 헤더가 "요일별 하루 7–23시 · 수면 시간 숨김"으로 바뀜
      - 검증(swiftc 12케이스): 자정 넘김/안 넘김, 낮잠, 수면 없음, 새벽 루틴·계획 보호,
        시각 미지정 블록, 비정상 수면 20시간, 이름 판별 4종, 좌표 매핑, 구간 절단
      - 🐞 테스트가 잡은 버그: 정오 클램프를 span 검사보다 **먼저** 적용해 4시간짜리 창이
        10시간으로 부풀려져 검사를 통과했다 → 순서 교정
- [x] 파랑 충돌 해소 — '남은 자유 시간'과 '계획'이 둘 다 파랑이라 헷갈림
      - `.accentColor`가 세 뜻으로 쓰이고 있었다: 계획 블록 / 남은 자유 시간 / 오늘·이번 주
      - 자유 시간은 '아직 계획이 없는 시간'이라 계획과 같은 색이면 뜻이 겹친다 →
        MetricCard의 `tint: .accentColor` 제거, 아무도 안 쓰게 된 `tint` 파라미터도 삭제
      - 주간 막대에서 남은 자유는 원래도 빈 구간(무채색)이었으므로 이제 카드와 막대가 같은 언어
      - 막대 범례 "남은 자유" → "남은 자유 (계획 없음)"
- [x] '오늘 / 이번 주' 강조를 파랑 → 빨강 (8곳)
      ContentView 이번 주 부제 / DayTimelineView 요일·날짜 / WeekGridView 요일·오늘 동그라미 /
      SharedScheduleSection 요일·날짜 / AllBacklogView 이번 주 헤더
      - 파랑은 이제 계획(구체적 블록·계획 막대)과 드롭 하이라이트에만 남음
      - [ ] ⚠️ 빨강이 '초과 배정'과 겹침: 타임라인 한 행에서 왼쪽 요일 숫자(오늘)와
            오른쪽 "남은 시간"(초과)이 둘 다 빨강이 될 수 있다.
            초과 쪽을 다른 표시로 옮길지 확인 필요
- [x] 폰트 확대 — 하드코딩 `.system(size:)` 65곳 상향 (8→10, 10→12, 11→13, 13→15, 18→20, 30→32),
      `.caption2` → `.caption`. 타임라인 행 폭·높이(26→30, 24→28, 90→96)를 축과 함께 맞춰 잘림 방지

- [x] '이번 주 계획' 항목에 수정 버튼
      - 진짜 구멍이었던 것: 고정 루틴·쿼터를 누르면 `RoutineDetailView`(정보·실행 전략·프리모템)만
        열리고 **이름·요일·시각을 바꾸는 편집기로 갈 길이 아예 없었다** (막다른 길)
      - `RoutineChip`·`BlockChip`에 호버 시 나타나는 '수정' 버튼 추가
      - 루틴 '수정' → `RoutineEditorView`(요일·시각), 칩 자체를 누르면 기존대로 상세
      - `RoutineDetailView` 헤더에도 '수정' 추가 — 상세에서 편집기로 갈 수 있게
      - ⚠️ Button 안에 Button을 넣으면 안쪽이 클릭을 못 받으므로, 칩 본체를
        `onTapGesture` + 오버레이 버튼으로 분리 (드래그 이동은 그대로 동작)

## 알려진 문제 (이 작업과 무관, 선행 커밋에서 유입)
- [ ] 서명 실패: 프로비저닝 프로파일이 `iCloud.com.Ysoup.FeedbackHub` 컨테이너를 지원하지 않음
      → Apple Developer 포털에서 App ID `com.devkoan.ScheduleDensityApp`에 해당 iCloud
      컨테이너를 추가해야 정상 빌드/실행 가능. (LeeoKit FeedbackHub 연동 커밋 이후)

## WeekBlocks 기능 백로그 (흡수)
- [ ] ConcretenessChecker Level 2 — 측정 가능 패턴 정규식
- [ ] ConcretenessChecker Level 3 — Claude API 판정
- [ ] 시간 그리드 / 블록 드래그 이동 / 반복 계획 블록
- [ ] 알림 / 메뉴바 위젯

## 완료 (2026-09-02) — 유료화(함께 쓰기) 구멍 메우기

- [x] StoreKit 설정 파일 신설 (`WeekBlocks.storekit`)
      - 비소모성 `com.devkoan.ScheduleDensityApp.sync` 한 개, `familyShareable: false`
      - `WeekBlocks.project.yml`의 스킴 run 액션에 `storeKitConfiguration`으로 연결
      - App Store Connect 승인 전에도 페이월·구매·복원 흐름을 로컬에서 굴려볼 수 있다
        (없으면 `Product.products()`가 빈 배열이라 '열기' 버튼이 영영 꺼져 있다)
      - Release/archive에는 안 붙는다 — 출시 빌드는 언제나 진짜 App Store를 본다
- [x] 켤 때 영수증 다시 읽기 (`WeekBlocksApp.swift`)
      - `.task { await PurchaseManager.shared.refresh() }` + scenePhase `.active` 복귀 시에도
      - 여태 페이월을 열 때만 읽어서, 다른 맥에서 산 사람이 잠긴 화면을 먼저 봐야 했다
- [x] `Transaction.updates`에서 거래 끝내기 (`MacEntitlement.swift`)
      - 안 끝내면 App Store가 켤 때마다 같은 거래를 다시 보낸다
        (다른 맥 구매·가족 공유·'구입 요청' 승인분이 특히 그렇다)
      - `purchase()`의 `.pending`/미검증도 말로 낸다 — 조용히 실패하면 버튼 고장으로 읽힌다
- [x] 설정에 '구매 복원' 자리 (`SettingsView.swift` → `purchaseSection`)
      - 여태 복원은 페이월 안에만 있었다. 페이월은 잠겼을 때만 열리는데, 사람은 설정에서 찾는다
      - `sellsAccess == false`면 통째로 감춘다 — 살 수도 없는 것의 복원 버튼은 고장으로 읽힌다

- [x] 무료 기간 유예 없애기 — '커튼'은 유지하되 새는 구멍만 막음
      - 결정: iCloud 미러링은 계속 켠다. 끄면 루틴·계획 동기화와 아이폰 할 일 받아보기까지
        함께 끊긴다 (한 컨테이너 한 스토어 — `Stores.swift:66`, `Stores.swift:8`의 금지 사항)
      - `MacEntitlement.hasPurchased` 신설 — `isUnlocked`(= sellsAccess 포함)와 갈랐다.
        '적을 수 있는가'와 '나눠 쓸 수 있는가'는 다른 질문이다
      - `TodoSharing.closeMyItems` + `reconcileMySharing` 신설
        · 샀다 → 내 줄을 연다 (기존 openMyItems)
        · 팔고 있는데 안 샀다 → 무료로 열려 있던 **내 줄만** 닫는다
        · 아직 팔기 전 → 아무것도 안 한다 (살 길이 없는 사람에게서 뺏지 않는다)
      - 내 줄만 뒤집으므로 양쪽이 반대로 뒤집으며 싸울 일이 없다. 닫아도 안 지운다 —
        내 화면엔 계속 보이고, 값을 치르면 openMyItems가 도로 연다
      - 호출: `WeekBlocksApp` (refresh **뒤에**), `BacklogView`의 isUnlocked onChange
      - 가족 공유: `.storekit`에 `familyShareable: false`. 앱 자체를 가족 공유로 받아도
        잠긴 기기라 적지 못하므로 새어나갈 것이 없다
- [x] 설정에 프로/무료 등급 표시 (`SettingsView.purchaseSection`)
      - 등급은 팔기 전에도 **언제나 보인다** (문의 왔을 때 서로 가리킬 자리)
      - 판정 근거는 `isUnlocked`가 아니라 `purchases.hasPurchased` — 무료 개방 기간에는
        적을 수 있어도 '무료'로 나온다
      - 사고·되찾는 단추는 `sellsAccess`가 켜졌을 때만 붙는다

## 완료 (2026-09-03) — 캘린더에서 일정 가져오기

- [x] `CalendarImport.swift` 신설 — EventKit 다리(`CalendarBridge`)
      - 설계: **계획 블록으로** / **캘린더 단위 선택** / **캘린더 → 앱 한 방향(읽기 전용)**
      - 권한: macOS 14부터 일정을 *읽으려면* 전체 접근이어야 한다. 쓰기 전용으로는 못 읽는다
        → `NSCalendarsFullAccessUsageDescription` + 샌드박스
        `com.apple.security.personal-information.calendars`
      - 아무 캘린더도 안 고르면 **아무것도 안 가져온다** (전부 가져오기를 기본으로 두면
        개인 일정이 주간 계획에 쏟아진다)
      - 반복 일정은 회차마다 `eventIdentifier`가 같다 → 키에 시작 시각을 붙여 가른다
      - 종일 일정은 24h가 아니라 1h + 시각 비움(`startHour = -1`).
        24h로 들이면 그 요일 자유 시간이 통째로 사라진다
      - 다시 가져오기: 새것 추가 / 시각·길이·제목만 갱신 / 사라진 것 정리.
        ⚠️ **사람이 손댄 블록(성공 기준·산출물·회고)은 지우지 않고 캘린더 연결만 끊는다**
- [x] `PlanBlock.calendarEventID` 추가 — nil이면 사람이 세운 블록, 가져오기가 안 건드린다
- [x] 설정에 캘린더 고르는 자리 (`SettingsView.calendarSection`)
- [x] 툴바 '더 보기 → 캘린더에서 가져오기' + 결과 알림
      (권한·선택이 없으면 설정으로 보낸다 — 아무 일도 안 일어나면 고장으로 읽힌다)

## 완료 (2026-09-03) — 첫 유료 출시 점검

- [x] **아이폰 앱에 같은 필터가 있는지 확인** (가장 중요했던 것)
      - iOS 저장소: `/Users/leeo/Documents/workspace/code/ScheduleDensity`
      - `Views/TodoView.swift:81` → `TodoTree(allItems.filter(TodoSharing.isVisible))`
      - `Shared/TodoSharing.swift`의 `isVisible`·`isMine`·`stamp` 규칙이 맥과 동일 ✅
      - 즉 맥이 `isShared = false`로 찍은 줄은 아이폰이 안 그린다 → 유료화가 실제로 작동
- [x] `MacEntitlement.sellsAccess = true`
      ⚠️ 첫 유료 출시라 **심사 빌드에 켜져 있어야 한다.** 꺼두면 심사자가 상품을 찾지 못해
         "unable to locate the in-app purchase"로 거절당한다.
      ⚠️ 켜는 순간 무료 기간에 적은 줄이 `closeMyItems`로 닫힌다 (의도한 '유예 없애기').
- [x] 프라이버시 매니페스트 (`PrivacyInfo.xcprivacy`) — 앱·확장 각각
      - UserDefaults(CA92.1) / 파일 타임스탬프(C617.1) / 디스크 여유(E174.1)
      - 없으면 업로드 뒤 ITMS-91053이 온다. Release 번들에 실제로 들어간 것 확인
- [x] `CloudSchemaPrimer.swift` 이식 (iOS → 맥, DEBUG 전용) + 설정에 실행 단추
      - CloudKit은 **값이 쓰인 필드만** 만든다. `calendarEventID` 같은 옵셔널은 표본을
        한 벌 올려야 Development 스키마에 칸이 생기고, 그래야 Production에 배포된다

### 남은 일 (App Store Connect — 콘솔에서)
- [ ] 유료 앱 계약 + 세금/은행 정보 (안 하면 상품이 아예 로드 안 된다)
- [ ] 비소모성 상품 생성 — ID `com.devkoan.ScheduleDensityApp.sync` (글자 하나까지 동일)
- [ ] **가족 공유 끄기** (기본이 꺼짐. 켜면 한 번 사서 6명이 쓴다)
- [ ] 가격·표시명·설명·심사용 스크린샷(페이월 화면)
- [ ] 앱 새 빌드와 **함께** 심사 제출 (IAP 단독 제출은 거절 잦음)
- [ ] 상품이 실제로 팔리기 시작하면 `MacEntitlement.sellsAccess = true`
- [ ] 출시 전 CloudKit 스키마 Development → Production 배포
      ⚠️ 이제 **배포할 것이 실제로 생겼다** — `PlanBlock.calendarEventID`가 새 필드다.
         디버그로 한 번 가져오기를 돌려 Development 스키마에 필드를 만든 뒤 배포할 것.
         (CloudKit 필드는 값이 실제로 저장될 때 생긴다)
